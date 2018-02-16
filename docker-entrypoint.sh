#!/usr/bin/env sh

[ -z "${CFSSL_CA_CN}" ] && echo "CFSSL_CA_CN must be set" && exit 1
[ -z "${CFSSL_AUTH_SERVER}" ] && echo "CFSSL_AUTH_SERVER must be set" && exit 1
[ -z "${CFSSL_AUTH_CLIENT}" ] && echo "CFSSL_AUTH_CLIENT must be set" && exit 1

CFSSL_AUTH_UNUSED=$(hexdump -n 16 -v -e '/1 "%02x"' /dev/urandom)
export CFSSL_AUTH_UNUSED
_config="/tmp/cfssl-config.json.$(hexdump -n 3 -v -e '/1 "%02x"' /dev/urandom)"
cat /etc/cfssl/config.json | envsubst > $_config

_workdir=/var/lib/cfssl

_setup_ca(){
    [ -f "${_workdir}/ca.pem" ] && _renew_by=$(( $(date -d "$(cfssl certinfo -cert=${_workdir}/ca.pem | jq -r '.not_after')" +%s) - 7 * 24 * 3600 ))

    [ -f "${_workdir}/ca-key.pem" ] && [ -f "${_workdir}/ca.pem" ] \
        && [ "$(date +%s)" -lt "${_renew_by}" ] \
        && return

    [ -f "${_workdir}/ca-key.pem" ] && _args="-ca-key=${_workdir}/ca-key.pem"
    cfssl gencert -initca ${_args} - << EOF | cfssljson -bare "${_workdir}/ca"
    { "CN": "${CFSSL_CA_CN}", "key": { "algo": "ecdsa", "size": 521 }, "ca": { "expiry": "${CFSSL_CA_EXPIRY_HOURS}h" } }
EOF
}

# initialise ca
_setup_ca

# run service
timeout \
    --preserve-status \
    --kill-after=30s \
    --foreground \
    1d cfssl serve \
        -address=0.0.0.0 \
        -port=8888 \
        -config="${_config}" \
        -ca=/var/lib/cfssl/ca.pem \
        -ca-key=/var/lib/cfssl/ca-key.pem
