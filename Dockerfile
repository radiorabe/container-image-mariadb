FROM quay.io/sclorg/mariadb-105-c9s:20251112 AS upstream
FROM ghcr.io/radiorabe/ubi9-minimal:0.10.2 AS build

ENV APP_DATA=/opt/app-root/src \
    CONTAINER_SCRIPTS_PATH=/usr/share/container-scripts/mysql \
    STI_SCRIPTS_PATH=/usr/libexec/s2i \
    HOME=/var/lib/mysql

COPY mariadb.repo /etc/yum.repos.d/

RUN    mkdir -p /mnt/rootfs \
    && microdnf install -y \
       --releasever 9 \
       --installroot /mnt/rootfs \
       --noplugins \
       --config /etc/dnf/dnf.conf \
       --setopt install_weak_deps=0 --nodocs \
       --setopt cachedir=/var/cache/dnf \
       --setopt reposdir=/etc/yum.repos.d \
       --setopt varsdir=/etc/yum.repos.d \
         policycoreutils \
         rsync \
         tar \
         gettext \
         hostname \
         bind-utils \
         groff-base

# Install a s2i like server, but using Oracles RPMs
# We can switch back to using what RedHat deems as stable/supported
# once our deployments catch up to being more modern.
RUN    chroot /mnt/rootfs groupadd --system --gid 27 mysql \
    && chroot /mnt/rootfs useradd \
         --no-create-home \
         --no-user-group \
         --shell /sbin/nologin \
         --uid 27 \
         --gid 27 \
         --system \
           mysql \
    && rpm --root /mnt/rootfs --import https://rpm.mariadb.org/RPM-GPG-KEY-MariaDB \
    && rpm -q --queryformat "%{SUMMARY}\n" $(rpm -q gpg-pubkey) \
    && microdnf install -y \
       --releasever 9 \
       --installroot /mnt/rootfs \
       --noplugins \
       --config /etc/dnf/dnf.conf \
       --setopt install_weak_deps=0 --nodocs \
       --setopt cachedir=/var/cache/dnf \
       --setopt reposdir=/etc/yum.repos.d \
       --setopt varsdir=/etc/yum.repos.d \
         MariaDB-server \
         MariaDB-client

RUN    cp \
         /etc/pki/ca-trust/source/anchors/rabe-ca.crt \
         /mnt/rootfs/etc/pki/ca-trust/source/anchors/ \
    && update-ca-trust \
    && rm \
         /mnt/rootfs/usr/bin/gsoelim \
         /mnt/rootfs/usr/sbin/rcmysql \
         /mnt/rootfs/usr/bin/soelim \
         /mnt/rootfs/usr/bin/zsoelim \
    && chmod -f a-s \
         /mnt/rootfs/usr/bin/* \
         /mnt/rootfs/usr/sbin/* \
         /mnt/rootfs/usr/libexec/*/* \
    && rm -rf \
         /mnt/rootfs/var/cache/* \
         /mnt/rootfs/var/log/dnf* \
         /mnt/rootfs/var/log/yum.*

COPY --from=upstream /usr/libexec/fix-permissions /usr/libexec/container-setup /mnt/rootfs/usr/libexec/
COPY --from=upstream /bin/cgroup-limits /bin/run-mysqld /bin/container-entrypoint /mnt/rootfs/bin/
COPY --from=upstream /etc/my.cnf /mnt/rootfs/etc/
COPY --from=upstream ${STI_SCRIPTS_PATH} /mnt/rootfs/${STI_SCRIPTS_PATH}
COPY --from=upstream ${CONTAINER_SCRIPTS_PATH} /mnt/rootfs/${CONTAINER_SCRIPTS_PATH}

RUN    chroot /mnt/rootfs ln -s /bin/mariadb-install-db /bin/mysql_install_db \
    && chroot /mnt/rootfs ln -s /bin/mariadb-admin /bin/mysqladmin \
    && chroot /mnt/rootfs ln -s /bin/mariadb-upgrade /bin/mysql_upgrade \
    && chroot /mnt/rootfs ln -s /bin/mariadb /bin/mysql \
    && chroot /mnt/rootfs ln -s /sbin/mariadbd /usr/libexec/mysqld \
    && rm -rf /mnt/rootfs/var/lib/mysql

FROM scratch AS app

ENV CONTAINER_SCRIPTS_PATH=/usr/share/container-scripts/mysql \
    STI_SCRIPTS_PATH=/usr/libexec/s2i \
    APP_DATA=/opt/app-root/src \
    MYSQL_PREFIX=/usr \
    MYSQL_VERSION=11.2

ENV STI_SCRIPTS_URL=image://${STI_SCRIPTS_PATH}

COPY --from=build /mnt/rootfs/ /

RUN    mkdir -p /var/lib/mysql/data && chown -R mysql.0 /var/lib/mysql \
    && test "$(id mysql)" = "uid=27(mysql) gid=27(mysql) groups=27(mysql)" \
    && rm -rf /etc/my.cnf.d/* \
    && /usr/libexec/container-setup

USER 27

ENTRYPOINT ["container-entrypoint"]
CMD ["run-mysqld"]
