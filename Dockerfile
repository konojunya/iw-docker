FROM alpine:3.5

RUN apk add --no-cache \
      git curl tar \
      openssh-client

ENV GOLANG_VERSION 1.8.3

RUN set -eux; \
    apk add --no-cache --virtual .build-deps \
        bash \
        gcc \
        musl-dev \
        openssl \
        go \
    ; \
        export \
# set GOROOT_BOOTSTRAP such that we can actually build Go
        GOROOT_BOOTSTRAP="$(go env GOROOT)" \
# ... and set "cross-building" related vars to the installed system's values so that we create a build targeting the proper arch
# (for example, if our build host is GOARCH=amd64, but our build env/image is GOARCH=386, our build needs GOARCH=386)
        GOOS="$(go env GOOS)" \
        GOARCH="$(go env GOARCH)" \
        GO386="$(go env GO386)" \
        GOARM="$(go env GOARM)" \
        GOHOSTOS="$(go env GOHOSTOS)" \
        GOHOSTARCH="$(go env GOHOSTARCH)" \
    ; \
    \
    wget -O go.tgz "https://golang.org/dl/go$GOLANG_VERSION.src.tar.gz"; \
    echo '5f5dea2447e7dcfdc50fa6b94c512e58bfba5673c039259fd843f68829d99fa6 *go.tgz' | sha256sum -c -; \
    tar -C /usr/local -xzf go.tgz; \
    rm go.tgz; \
    \
    cd /usr/local/go/src; \
    ./make.bash; \
    \
    apk del .build-deps; \
    \
    export PATH="/usr/local/go/bin:$PATH"; \
    go version

ENV GOPATH /go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH

RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" \
    && chmod -R 777 "$GOPATH" \
    && apk add --no-cache musl-dev build-base \
    && go get github.com/rubenv/sql-migrate/... \
    && which sql-migrate

RUN apk add --no-cache make py-pip bash jq ca-certificates
RUN pip install --no-cache-dir awscli awslogs

ENV DOCKER_CHANNEL stable
ENV DOCKER_VERSION 17.06.1-ce
# TODO ENV DOCKER_SHA256
# https://github.com/docker/docker-ce/blob/5b073ee2cf564edee5adca05eee574142f7627bb/components/packaging/static/hash_files !!
# (no SHA file artifacts on download.docker.com yet as of 2017-06-07 though)

RUN set -ex; \
# why we use "curl" instead of "wget":
# + wget -O docker.tgz https://download.docker.com/linux/static/stable/x86_64/docker-17.03.1-ce.tgz
# Connecting to download.docker.com (54.230.87.253:443)
# wget: error getting response: Connection reset by peer
    apk add --no-cache --virtual .fetch-deps \
        curl \
        tar \
    ; \
    \
# this "case" statement is generated via "update.sh"
    apkArch="$(apk --print-arch)"; \
    case "$apkArch" in \
        x86_64) dockerArch='x86_64' ;; \
        s390x) dockerArch='s390x' ;; \
        *) echo >&2 "error: unsupported architecture ($apkArch)"; exit 1 ;;\
    esac; \
    \
    if ! curl -fL -o docker.tgz "https://download.docker.com/linux/static/${DOCKER_CHANNEL}/${dockerArch}/docker-${DOCKER_VERSION}.tgz"; then \
        echo >&2 "error: failed to download 'docker-${DOCKER_VERSION}' from '${DOCKER_CHANNEL}' for '${dockerArch}'"; \
        exit 1; \
    fi; \
    \
    tar --extract \
        --file docker.tgz \
        --strip-components 1 \
        --directory /usr/local/bin/ \
    ; \
    rm docker.tgz; \
    \
    apk del .fetch-deps; \
    \
    dockerd -v; \
    docker -v

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["sh"]