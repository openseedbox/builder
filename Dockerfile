# syntax=docker/dockerfile:1

FROM eclipse-temurin:11-jdk AS java
RUN jlink \
        --add-modules \
                java.base,java.compiler,java.datatransfer,java.desktop,java.instrument,java.logging,java.management,java.management.rmi,java.naming,java.prefs,java.rmi,java.scripting,java.security.jgss,java.security.sasl,java.sql,java.sql.rowset,java.transaction.xa,java.xml,jdk.crypto.cryptoki,jdk.jdi,jdk.management,jdk.unsupported \
        --output /java/ \
        --strip-debug \
        --no-man-pages \
        --compress=2


FROM tomcat:10.1.0-jre11-temurin as tomcat
#------------------------^
# openjdk doesn't have linux/arm/v7 platform :(
# Enable Tomcat HealthCheck endpoint
RUN sed -i '/^               pattern=.*/a\\t<Valve className="org.apache.catalina.valves.HealthCheckValve" />' /usr/local/tomcat/conf/server.xml;


FROM debian:bullseye-slim as openseedbox
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
RUN bash -c "for repo in openseedbox{-common,-server,}; do echo cloning \$repo; git clone --depth=1 -q https://github.com/openseedbox/\$repo ; done"


FROM debian:bullseye-slim AS builder
COPY --from=java /java /java
ENV JAVA_HOME=/java

COPY --from=tomcat /usr/local/tomcat /tomcat
COPY --from=openseedbox /src /src
COPY --from=openseedbox /play /play

