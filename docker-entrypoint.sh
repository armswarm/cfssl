#!/usr/bin/env sh

set -o errexit

_usage() {
    echo "usage: /docker-entrypoint.sh <service|newcert>" && exit 1
}

_cert_should_renew() {
    [ -f "${1}.pem" ] \
        && [ -f "${1}-key.pem" ] \
        && [ "$(date +%s)" -lt $(( $(date -d "$(cfssl certinfo -cert=${1}.pem | jq -r '.not_after')" +%s) - 7 * 24 * 3600 )) ] \
        && return 1 \
        || return 0
}

_setup_ca(){
    _cert_should_renew "${_workdir}/ca" || return 0

    [ -f "${_workdir}/ca-key.pem" ] && _args="-ca-key=${_workdir}/ca-key.pem"
    [ ! -z "${CFSSL_CA_O}" ] && _extras=", \"names\": [ {\"O\": \"${CFSSL_CA_O}\"} ]"
    cfssl gencert -initca ${_args} - << EOF | cfssljson -bare "${_workdir}/ca"
    { "CN": "${CFSSL_CA_CN}", "key": { "algo": "ecdsa", "size": 521 }, "ca": { "expiry": "${CFSSL_CA_EXPIRY_HOURS}h" }${_extras} }
EOF
}

_newcert() {
    _output_path="${1:-/out}"

    [ "${CERT_FORCE_RENEW}" != "yes" ] && ! _cert_should_renew "${_output_path}/${CERT_CN}" \
        && echo "certificate is still valid, set CERT_FORCE_RENEW=yes to override" && return

    _cert_hostname="${CERT_CN}"
    [ ! -z "${CERT_O}" ] && _cert_o='"names":[{"O":"'"${CERT_O}"'"}],'
    [ ! -z "${CERT_SAN_LIST}" ] && _cert_hostname="${_cert_hostname},${CERT_SAN_LIST}"

    cfssl gencert \
      -config="${_config}" \
      -profile"=${CFSSL_PROFILE}" \
      -hostname="${_cert_hostname}" - << EOF | cfssljson -bare "${_output_path}/${CERT_CN}"
    {"CN":"${CERT_CN}",${_cert_o}"key":{"algo":"ecdsa","size":384}}
EOF

    cfssl info -config="${_config}" | cfssljson -bare "${_output_path}/ca"

}

[ "$#" -ne 1 ] || [ "${1}" != "service" ] && [ "${1}" != "newcert" ] && _usage

if [ "${1}" = "newcert" ]; then
    # validate input
    [ -z "${CFSSL_HOST}" ] && echo "CFSSL_HOST must be set" && exit 1
    [ -z "${CFSSL_AUTH_KEY}" ] && echo "CFSSL_AUTH_KEY must be set" && exit 1
    [ -z "${CFSSL_PROFILE}" ] && echo "CFSSL_PROFILE must be set" && exit 1
    [ -z "${CERT_CN}" ] && echo "CERT_CN must be set" && exit 1

    # create config
    _config="/tmp/cfssl-config-client.json.$(hexdump -n 3 -v -e '/1 "%02x"' /dev/urandom)"
    cat /etc/cfssl/config-client.json | envsubst > $_config

    # generate certificate
    _newcert

elif [ "${1}" = "service" ]; then
    [ -z "${CFSSL_CA_CN}" ] && echo "CFSSL_CA_CN must be set" && exit 1
    [ -z "${CFSSL_AUTH_SERVER}" ] && echo "CFSSL_AUTH_SERVER must be set" && exit 1
    [ -z "${CFSSL_AUTH_CLIENT}" ] && echo "CFSSL_AUTH_CLIENT must be set" && exit 1

    CFSSL_AUTH_UNUSED=$(hexdump -n 16 -v -e '/1 "%02x"' /dev/urandom)
    export CFSSL_AUTH_UNUSED
    _config="/tmp/cfssl-config-service.json.$(hexdump -n 3 -v -e '/1 "%02x"' /dev/urandom)"
    cat /etc/cfssl/config-service.json | envsubst > $_config

    _workdir=/var/lib/cfssl

    # initialise ca
    _setup_ca

    # run the service; timeout every day (should be restarted by dockerd) to
    # ensure we have a valid CA
    timeout \
        --preserve-status \
        --kill-after=30s \
        --foreground \
        1d cfssl serve \
            -address=0.0.0.0 \
            -port=8888 \
            -config="${_config}" \
            -ca="${_workdir}/ca.pem" \
            -ca-key="${_workdir}/ca-key.pem"

else
    _usage
fi
