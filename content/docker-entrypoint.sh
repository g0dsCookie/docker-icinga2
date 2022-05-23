#!/bin/bash

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

if [[ -f /etc/icinga2/.nomount ]]; then
    get_type

    if ! j2 /templates/icinga2.conf.j2 "${CONFIG}" >/etc/icinga2/icinga2.conf; then
        echo "Failed to create templated config"
        exit 1
    fi

    NODENAME="$(cfg '.node.name')"
    [[ "${NODENAME}" != "null" ]] || NODENAME="$(hostname -f)"

    if [[ ! -f "/var/lib/icinga2/certs/${NODENAME}.crt" ]]; then
        if [[ -n "${ICINGA_PKI:-}" ]]; then
            # register as agent/satellite
            mkdir -p /var/lib/icinga2/certs

            if [[ -z "${ICINGA_CA_NODE:-}" ]]; then
                ICINGA_CA_NODE="$(jq -r '.endpoints[0].host' /config/icinga2.json)"
                ICINGA_CA_PORT="$(jq -r '.endpoints[0].port' /config/icinga2.json)"

                if [[ "${ICINGA_CA_NODE}" == "null" ]]; then
                    echo "Missing ICINGA_CA_NODE environment or .endpoints[0] for master"
                    exit 1
                fi
                [[ "${ICINGA_CA_PORT}" != "null" ]] || ICINGA_CA_PORT="5665"
            fi

            # generate self-signed certificate
            icinga2 pki new-cert --cn "${NODENAME}" \
                --cert "/var/lib/icinga2/certs/${NODENAME}.crt" \
                --csr "/var/lib/icinga2/certs/${NODENAME}.csr" \
                --key "/var/lib/icinga2/certs/${NODENAME}.key"

            # receive trusted certificate from ca master
            icinga2 pki save-cert \
                --host "${ICINGA_CA_NODE}" \
                --port "${ICINGA_CA_PORT}" \
                --key "/var/lib/icinga2/certs/${NODENAME}.key" \
                --trustedcert "/var/lib/icinga2/certs/trusted-master.crt"

            # generate final certificate
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
            mkdir -p /var/lib/icinga2/certs
            if [[ ! -f /var/lib/icinga2/ca/ca.crt ]]; then
                # create new ca
                icinga2 pki new-ca
                cp /var/lib/icinga2/ca/ca.crt /var/lib/icinga2/certs/ca.crt
            fi
            icinga2 pki new-cert --cn "${NODENAME}" \
                --csr "/var/lib/icinga2/certs/${NODENAME}.csr" \
                --key "/var/lib/icinga2/certs/${NODENAME}.key"
            icinga2 pki sign-csr \
                --csr "/var/lib/icinga2/certs/${NODENAME}.csr" \
                --cert "/var/lib/icinga2/certs/${NODENAME}.crt"
        fi
    fi

    ### validate
    # verify cn in cert
    icinga2 pki verify --cn "${NODENAME}" \
        --cert "/var/lib/icinga2/certs/${NODENAME}.crt"
    # verify cert is signed by ca
    icinga2 pki verify \
        --cert "/var/lib/icinga2/certs/${NODENAME}.crt" \
        --cacert "/var/lib/icinga2/certs/ca.crt"
fi

exec icinga2 daemon