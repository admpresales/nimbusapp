FROM perl:5.20

RUN set -xe; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        zip \
    ; \
    rm -rf /var/lib/apt/lists/*

COPY cpanfile /
RUN cpanm / --installdeps
