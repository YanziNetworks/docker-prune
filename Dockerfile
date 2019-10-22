FROM docker:19.03.4

LABEL maintainer="efrecon@gmail.com"
LABEL org.label-schema.build-date=${BUILD_DATE}
LABEL org.label-schema.schema-version="1.0"
LABEL org.label-schema.name="yanzinetworks/prune"
LABEL org.label-schema.description="Conservative Docker system prune"
LABEL org.label-schema.url="https://github.com/YanziNetworks/docker-prune"
LABEL org.label-schema.docker.cmd="docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock:ro yanzinetworks/prune --verbose"

ADD prune.sh /usr/local/bin/prune.sh
ENTRYPOINT [ "/usr/local/bin/prune.sh" ]
