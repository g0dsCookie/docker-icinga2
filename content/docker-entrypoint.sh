#!/bin/bash

set -eu

get_type() {
    [[ -z "${CONFIG:-}" ]] || return
    declare -g CONFIG TYPE
    for cfg in yaml json; do
        if [[ -f "/config/icinga2.${cfg}" ]]; then
            TYPE="${cfg}"
            CONFIG="/config/icinga2.${cfg}"
            break
        fi
    done
    if [[ -z "${CONFIG}" ]]; then
        echo "Could not find config file"
        exit 1
    fi
}

cfg() {
    local option="$1"
    get_type

    case "${TYPE}" in
        json) jq -r "${option}" "${CONFIG}" ;;
        yaml) yq e "${option}" "${CONFIG}" ;;
        *)
            echo "Unknown config type ${TYPE}" >&2
            exit 1
        ;;
    esac
}

NAGIOS_UID="$(id -u nagios)"
EFFECTIVE_UID="$(id -u)"
ICINGADIR_UID="$(stat -c %u /var/lib/icinga2)"

if [[ "${ICINGADIR_UID}" != "${NAGIOS_UID}" ]]; then
    # icinga dir not owned by nagios, try changing it
    if [[ "${EFFECTIVE_UID}" == "0" ]]; then
        chown -R nagios:nagios /var/lib/icinga2
    else
        # we are not root and can't change owners
        echo "#####################################################################"
        echo "### Icinga dir owned by ${ICINGADIR_UID} instead of ${NAGIOS_UID} ###"
        echo "### Entrypoint is not started as root, thus we can't change it    ###"
        echo "### If you run into trouble, try fixing the permissions first     ###"
        echo "#####################################################################"
    fi
fi

if [[ -f /etc/icinga2/.nomount ]]; then
    get_type

    if ! j2 /templates/icinga2.conf.j2 "${CONFIG}" >/etc/icinga2/icinga2.conf; then
        echo "Failed to create templated config"
        exit 1
    fi

    NODENAME="$(cfg '.node.name')"
    [[ "${NODENAME}" != "null" ]] || NODENAME="$(hostname -f)"

    if [[ ! -d "/var/lib/icinga2/certs" ]]; then
        mkdir -p /var/lib/icinga2/certs
        chown nagios:nagios /var/lib/icinga2/certs
    fi

    if [[ ! -f "/var/lib/icinga2/certs/${NODENAME}.crt" ]]; then
        if [[ -n "${ICINGA_PKI:-}" ]]; then
            # register as agent/satellite
            if [[ -z "${ICINGA_CA_NODE:-}" ]]; then
                ICINGA_CA_NODE="$(cfg '.ca.host')"
                ICINGA_CA_PORT="$(cfg '.ca.port')"

                if [[ "${ICINGA_CA_NODE}" == "null" ]]; then
                    echo "Missing ICINGA_CA_NODE environment or .ca.(host|port) for master"
                    exit 1
                fi
            fi
            if [[ -z "${ICINGA_CA_PORT}" || "${ICINGA_CA_PORT}" == "null" ]]; then
                ICINGA_CA_PORT="5665"
            fi

            # generate self-signed certificate
            echo "### GENERATING SELF-SIGNED CERTIFICATE ###"
            icinga2 pki new-cert --cn "${NODENAME}" \
                --cert "/var/lib/icinga2/certs/${NODENAME}.crt" \
                --csr "/var/lib/icinga2/certs/${NODENAME}.csr" \
                --key "/var/lib/icinga2/certs/${NODENAME}.key"

            # receive trusted certificate from ca master
            echo "### RECEIVE TRUSTED CERTIFICATE ###"
            icinga2 pki save-cert \
                --host "${ICINGA_CA_NODE}" \
                --port "${ICINGA_CA_PORT}" \
                --key "/var/lib/icinga2/certs/${NODENAME}.key" \
                --trustedcert "/var/lib/icinga2/certs/trusted-master.crt"

            # generate final certificate
            echo "### REQUEST FINAL CERTIFICATE ###"
            icinga2 pki request \
                --host "${ICINGA_CA_NODE}" \
                --port "${ICINGA_CA_PORT}" \
                --ticket "${ICINGA_PKI}" \
                --cert "/var/lib/icinga2/certs/${NODENAME}.crt" \
                --key "/var/lib/icinga2/certs/${NODENAME}.key" \
                --trustedcert "/var/lib/icinga2/certs/trusted-master.crt" \
                --ca "/var/lib/icinga2/certs/ca.crt"
        else
            # master setup
            if [[ ! -f /var/lib/icinga2/ca/ca.crt ]]; then
                # create new ca
                echo "### GENERATING NEW CA ###"
                icinga2 pki new-ca
                cp /var/lib/icinga2/ca/ca.crt /var/lib/icinga2/certs/ca.crt
            fi
            echo "### GENERATING MASTER CERTIFICATE ###"
            icinga2 pki new-cert --cn "${NODENAME}" \
                --csr "/var/lib/icinga2/certs/${NODENAME}.csr" \
                --key "/var/lib/icinga2/certs/${NODENAME}.key"
            echo "### SIGNING MASTER CERTIFICATE WITH CA ###"
            icinga2 pki sign-csr \
                --csr "/var/lib/icinga2/certs/${NODENAME}.csr" \
                --cert "/var/lib/icinga2/certs/${NODENAME}.crt"
        fi
    fi

    ### validate
    echo "### RUNNING SANITY CHECKS ON CERTIFICATES ###"
    # verify cn in cert
    icinga2 pki verify --cn "${NODENAME}" \
        --cert "/var/lib/icinga2/certs/${NODENAME}.crt"
    # verify cert is signed by ca
    icinga2 pki verify \
        --cert "/var/lib/icinga2/certs/${NODENAME}.crt" \
        --cacert "/var/lib/icinga2/certs/ca.crt"
fi

exec icinga2 daemon