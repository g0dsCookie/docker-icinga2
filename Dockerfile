FROM debian:11 AS icinga

ARG ICINGA2_VERSION
ARG REVISION

LABEL maintainer="g0dsCookie <g0dscookie@cookieprojects.de>" \
      description="The core of our monitoring platform with a powerful configuration language and REST API" \
      version="${ICINGA2_VERSION}"

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eu \
 && apt-get update -qqy \
 && apt-get upgrade -qqy \
 && apt-get install -qy apt-transport-https wget gnupg \
 && apt-get autoremove -qqy \
 && apt-get clean -qqy

ARG YQ_VERSION=4.25.1
RUN set -eu \
 && PLATFORM="$(uname -m)" \
 && if [ "${PLATFORM}" = "x86_64" ]; then export YQ_PLATFORM="amd64"; export FLAVOR="debian"; else export YQ_PLATFORM="arm"; export FLAVOR="raspbian"; fi \
 && wget -O /usr/bin/yq "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${YQ_PLATFORM}" \
 && chmod +x /usr/bin/yq

RUN set -eu \
 && PLATFORM="$(uname -m)" \
 && if [ "${PLATFORM}" = "x86_64" ]; then export YQ_PLATFORM="amd64"; export FLAVOR="debian"; else export YQ_PLATFORM="arm"; export FLAVOR="raspbian"; fi \
 && echo "${ICINGA2_VERSION}" >ver \
 && IFS='.' read MAJOR MINOR PATCH <ver && rm -f ver \
 && wget -O - https://packages.icinga.com/icinga.key | apt-key add - \
 && DIST=$(awk -F"[)(]+" '/VERSION=/ {print $2}' /etc/os-release) \
 && echo "deb https://packages.icinga.com/${FLAVOR} icinga-${DIST} main" >/etc/apt/sources.list.d/${DIST}-icinga.list \
 && echo "deb-src https://packages.icinga.com/${FLAVOR} icinga-${DIST} main" >>/etc/apt/sources.list.d/${DIST}-icinga.list \
 && apt-get update -qqy \
 && APTVER="${ICINGA2_VERSION}-${REVISION}.${DIST}" \
 && apt-get install -qqy \
      icinga2=${APTVER} icinga2-ido-mysql=${APTVER} \
      monitoring-plugins monitoring-plugins-contrib monitoring-plugins-btrfs \
      j2cli jq sudo \
 && apt-get remove -qqy icinga2-doc \
 && apt-get autoremove -qqy \
 && apt-get clean -qqy

RUN set -eu \
 && mkdir -p /usr/local/share/ca-certificates \
 && chown nagios:nagios /usr/local/share/ca-certificates \
 && chmod 0755 /usr/local/share/ca-certificates

RUN set -eu \
 && usermod -s /bin/bash nagios \
 && echo "nagios ALL = (root:root) NOPASSWD: /usr/bin/apt-get update, /usr/bin/apt-get clean, /usr/bin/apt-get install *" >/etc/sudoers.d/nagios \
 && echo "nagios ALL = (root:root) NOPASSWD: /usr/sbin/groupadd *, /usr/bin/gpasswd *" >>/etc/sudoers.d/nagios \
 && echo "nagios ALL = (root:root) NOPASSWD: /usr/sbin/update-ca-certificates" >>/etc/sudoers.d/nagios \
 && echo "nagios ALL = (root:root) NOPASSWD: /bin/su -s /bin/bash nagios -c icinga2\ daemon" >>/etc/sudoers.d/nagios \
 && rm -rf /etc/icinga2/* && touch /etc/icinga2/.nomount \
 && mkdir /plugins /config && chown root:root /plugins /config && chmod 0755 /plugins /config \
 && mkdir /run/icinga2 && chown nagios:nagios /run/icinga2

COPY --chown=root:root content/ /

EXPOSE 5665
VOLUME [ "/var/lib/icinga2", "/plugins" ]
USER nagios
ENTRYPOINT [ "/docker-entrypoint.sh" ]