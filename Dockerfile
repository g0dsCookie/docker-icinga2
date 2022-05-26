FROM debian:11 AS icinga

ARG ICINGA2_VERSION
ARG YQ_VERSION=4.25.1
ARG REVISION

LABEL maintainer="g0dsCookie <g0dscookie@cookieprojects.de>" \
      description="A fast and secure drop-in replacement for sendmail" \
      version="${ICINGA2_VERSION}"

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eu \
 && PLATFORM="$(uname -m)" \
 && if [ "${PLATFORM}" = "x86_64" ]; then export YQ_PLATFORM="amd64"; export FLAVOR="debian"; else export YQ_PLATFORM="arm"; export FLAVOR="raspbian"; fi \
 && ICINGA2_VERSION="$(echo ${ICINGA2_VERSION} | sed 's/^v//')" \
 && echo "${ICINGA2_VERSION}" >ver \
 && IFS='.' read MAJOR MINOR PATCH <ver && rm -f ver \
 && cecho() { echo "\033[1;32m$1\033[0m"; } \
 && cecho "### PREPARE ENVIRONMENT ###" \
 && TMP="$(mktemp -d)" && PV="${ICINGA2_VERSION}" && S="${TMP}/icinga2-${PV}" \
 && apt-get update -qqy \
 && apt-get upgrade -qqy \
 && cecho "### UPDATE APT REPOSITORIES ###" \
 && apt-get install -qqy apt-transport-https wget gnupg \
 && wget -O - https://packages.icinga.com/icinga.key | apt-key add - \
 && DIST=$(awk -F"[)(]+" '/VERSION=/ {print $2}' /etc/os-release) \
 && echo "deb https://packages.icinga.com/${FLAVOR} icinga-${DIST} main" >/etc/apt/sources.list.d/${DIST}-icinga.list \
 && echo "deb-src https://packages.icinga.com/${FLAVOR} icinga-${DIST} main" >>/etc/apt/sources.list.d/${DIST}-icinga.list \
 && apt-get update -qqy \
 && cecho "### INSTALLING YQ ###" \
 && wget -O /usr/bin/yq "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${YQ_PLATFORM}" \
 && chmod +x /usr/bin/yq \
 && cecho "### INSTALLING ICINGA2 ###" \
 && APTVER="${ICINGA2_VERSION}-${REVISION}.${DIST}" \
 && apt-get install -qqy \
      icinga2=${APTVER} icinga2-ido-mysql=${APTVER} \
      monitoring-plugins monitoring-plugins-contrib monitoring-plugins-btrfs \
      j2cli jq sudo \
 && cecho "### FINISH & CLEANUP ###" \
 && echo "nagios ALL = (root:root) NOPASSWD: /usr/bin/apt-get update, /usr/bin/apt-get clean, /usr/bin/apt-get install *" >/etc/sudoers.d/nagios \
 && rm -rf /etc/icinga2/* && touch /etc/icinga2/.nomount \
 && mkdir /plugins /config && chown root:root /plugins /config && chmod 0755 /plugins /config \
 && mkdir /run/icinga2 && chown nagios:nagios /run/icinga2 \
 && apt-get remove -qqy icinga2-doc \
 && apt-get autoremove -qqy \
 && apt-get clean -qqy

COPY --chown=root:root content/ /

EXPOSE 5665
VOLUME [ "/var/lib/icinga2", "/plugins" ]
USER nagios
ENTRYPOINT [ "/docker-entrypoint.sh" ]