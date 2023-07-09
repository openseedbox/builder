# syntax=docker/dockerfile:1

FROM debian:bullseye-slim AS base-image
# for real language support please install "locales" package!
ENV LANG=C.UTF-8


FROM eclipse-temurin:11-jdk AS java
RUN jlink \
        --add-modules \
                java.base,java.compiler,java.datatransfer,java.desktop,java.instrument,java.logging,java.management,java.management.rmi,java.naming,java.prefs,java.rmi,java.scripting,java.security.jgss,java.security.sasl,java.sql,java.sql.rowset,java.transaction.xa,java.xml,jdk.crypto.cryptoki,jdk.jdi,jdk.management,jdk.unsupported \
        --output /java/ \
        --strip-debug \
        --no-man-pages \
        --compress=2


FROM tomcat:10.1.9-jre11-temurin-jammy as tomcat
#------------------------^
# openjdk doesn't have linux/arm/v7 platform :(

# install yq for $CATALINA_HOME/conf/server.xml editing
RUN apt update -qq && apt install -y --no-install-recommends \
	python3-pip jq \
	&& pip install yq

# disable SSL support (and so the OpenSSL requirement) by removing the listener itself
# switching off doesn't help.
# see https://github.com/openseedbox/openseedbox/issues/93 for the details!
RUN xq -x '.Server.Listener|=map(select(."@className"!="org.apache.catalina.core.AprLifecycleListener"))' conf/server.xml > noapr.xml && mv -v noapr.xml conf/server.xml

# Enable Tomcat HealthCheck endpoint
RUN xq --xml-force-list 'Valve' -x '.Server.Service.Engine.Host.Valve+=[{"@className": "org.apache.catalina.valves.HealthCheckValve"}]' conf/server.xml > healthcheck.xml && mv -v healthcheck.xml conf/server.xml;

# remove webapps.dist as we don't need it
# about webapps.dist: https://github.com/docker-library/tomcat/commit/807a2b4f219d70f5ba6f4773d4ee4ee155850b0d
RUN rm -rf ${CATALINA_HOME}/webapps.dist


FROM base-image as tomcat-with-custom-jdk
# Copy Java
COPY --from=java /java /java
ENV JAVA_HOME=/java
ENV PATH $JAVA_HOME/bin:$PATH

# Mimic Tomcat image (copy-paste from https://github.com/docker-library/tomcat)
COPY --from=tomcat /usr/local/tomcat /tomcat
ENV CATALINA_HOME /tomcat
ENV PATH $CATALINA_HOME/bin:$PATH
WORKDIR $CATALINA_HOME

# ... without Tomcat Native
RUN rm -rfv $CATALINA_HOME/native-jni-lib

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends curl; \
	rm -rf /var/lib/apt/lists/*

# verify Tomcat config is working properly
RUN catalina.sh configtest 2>&1

EXPOSE 8080
CMD ["catalina.sh", "run"]

HEALTHCHECK --start-period=3s CMD curl --fail --silent --show-error --get http://localhost:8080/health


FROM base-image as openseedbox
RUN apt update -qq && apt install -y --no-install-recommends \
        git zip unzip python ca-certificates curl;

# Install play
ENV PLAY_VERSION=1.4.6
RUN curl -S -s -O "https://downloads.typesafe.com/play/${PLAY_VERSION}/play-${PLAY_VERSION}.zip" \
        && unzip -q play-${PLAY_VERSION}.zip \
        && rm -rf play-${PLAY_VERSION}/documentation/ play-${PLAY_VERSION}/samples-and-tests/ \
        && mv play-${PLAY_VERSION} /play \
        && rm play-${PLAY_VERSION}.zip

# Install siena module to play
RUN echo y | /play/play install siena-2.0.7 || echo "Downloading directly ... " \
        && curl -S -s -L -o siena-2.0.7.zip "https://www.playframework.com/modules/siena-2.0.7.zip" \
        && for zipfile in *.zip; do module="${zipfile%.zip}"; unzip -d /play/modules/"$module" "$zipfile"; rm "$zipfile"; done;

# Clone OpenSeedbox
WORKDIR /src
ARG CACHEBUSTER
RUN bash -c "for repo in openseedbox{-common,-server,}; do echo cloning \$repo; git clone --depth=1 -q https://github.com/openseedbox/\$repo ; done"


FROM base-image AS builder
COPY --from=java /java /java
ENV JAVA_HOME=/java

COPY --from=openseedbox /src /src
COPY --from=openseedbox /play /play
