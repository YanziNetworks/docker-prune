ARG DOCKER_VERSION=19.03.8
FROM docker:${DOCKER_VERSION}

# OCI Meta information
LABEL org.opencontainers.image.authors="efrecon@gmail.com"
LABEL org.opencontainers.image.created=${BUILD_DATE}
LABEL org.opencontainers.image.version="1.1"
LABEL org.opencontainers.image.url="https://github.com/YanziNetworks/docker-prune"
LABEL org.opencontainers.image.source="https://github.com/YanziNetworks/docker-prune"
LABEL org.opencontainers.image.documentation="https://github.com/YanziNetworks/docker-prune/README.md"
LABEL org.opencontainers.image.vendor="YanziNetworks AB"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.title="yanzinetworks/prune"
LABEL org.opencontainers.image.description="Conservative Docker system prune"

# Makes explicit environment variables, good defaults inside.
ENV BUSYBOX=
ENV MAXFILES=
ENV NAMES=
ENV EXCLUDE=
ENV RESOURCES=
ENV AGE=
ENV ANCIENT=
ENV TIMEOUT=

# Add dependency and main script
ADD lib/yu.sh /usr/local/lib/yu.sh
ADD prune.sh /usr/local/bin/prune.sh
ENTRYPOINT [ "/usr/local/bin/prune.sh" ]

# Failsafe: Nothing will happened when started without an arguments.
CMD [ "--help" ]