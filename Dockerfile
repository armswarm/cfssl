FROM quay.io/armswarm/alpine:3.7

ARG CFSSL_VERSION

ENV CFSSL_VERSION=$CFSSL_VERSION \
    CFSSL_CA_EXPIRY_HOURS=43630 \
    CFSSL_CERT_EXPIRY_HOURS=8760

ADD config.json /etc/cfssl/config.json
ADD docker-entrypoint.sh /

RUN \
    apk add --no-cache \
        coreutils \
        curl \
        gettext \
        jq \
    && curl -so /usr/local/bin/cfssl "https://pkg.cfssl.org/${CFSSL_VERSION}/cfssl_linux-arm" \
    && curl -so /usr/local/bin/cfssljson "https://pkg.cfssl.org/${CFSSL_VERSION}/cfssljson_linux-arm" \
    && chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson \
    && mkdir -p /var/lib/cfssl

VOLUME /var/lib/cfssl

EXPOSE 8888

ENTRYPOINT [ "/docker-entrypoint.sh" ]
