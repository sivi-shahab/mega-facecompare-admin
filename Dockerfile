# ==========================================
# Stage Build Application
# ==========================================
FROM imageregistry.bankmegadev.com:5000/maven/maven:3.8.2-eclipse-temurin-17 AS builder

# Proxy
ENV http_proxy=http://10.190.21.24:3128
ENV https_proxy=http://10.190.21.24:3128
ENV no_proxy=localhost,127.0.0.1,.bankmega.com
ENV HTTP_PROXY=http://10.190.21.24:3128
ENV HTTPS_PROXY=http://10.190.21.24:3128
ENV NO_PROXY=localhost,127.0.0.1,.bankmega.com

WORKDIR /workspace/compreface

# Opsional: opsi JVM untuk Maven di dalam build (mis. proxy: -Dhttps.proxyHost=... -Dhttps.proxyPort=...). Kosong = default.
ARG MAVEN_OPTS=""
# Layer dependency: hanya pom → cache Maven tetap valid selama pom tidak berubah.
# Copy dependency files
COPY java/pom.xml ./
COPY java/maven-settings.xml /root/.m2/settings.xml
COPY java/common/pom.xml common/
COPY java/admin/pom.xml admin/

RUN --mount=type=cache,target=/root/.m2/repository \
    mvn -B -q -pl admin -am dependency:go-offline \
    -Dmaven.gitcommitid.skip

COPY java/common common
COPY java/admin admin

RUN --mount=type=cache,target=/root/.m2/repository \
    mvn -B -pl admin -am package \
    -Dmaven.test.skip=true \
    -Dmaven.site.skip=true \
    -Dmaven.javadoc.skip=true \
    -Dcheckstyle.skip \
    -Djacoco.skip \
    -Dmaven.gitcommitid.skip \
 && cp admin/target/frs-crud-app-*.jar /workspace/app.jar


# ==========================================
# Stage Final App
# ==========================================
FROM imageregistry.bankmegadev.com:5000/eclipse/eclipse-temurin:17.0.8_7-jre-focal AS base

ENV http_proxy=http://10.190.21.24:3128
ENV https_proxy=http://10.190.21.24:3128
ENV no_proxy=localhost,127.0.0.1,.bankmega.com
ENV HTTP_PROXY=http://10.190.21.24:3128
ENV HTTPS_PROXY=http://10.190.21.24:3128
ENV NO_PROXY=localhost,127.0.0.1,.bankmega.com

# Default non-rahasia; override lewat env / ConfigMap.
ENV ADMIN_JAVA_OPTS="-XX:MaxRAMPercentage=75.0" 
ENV SPRING_PROFILES_ACTIVE=dev 
ENV MANAGEMENT_SERVER_PORT=8081 
ENV MANAGEMENT_HEALTH_MAIL_ENABLED=false 
ENV MANAGEMENT_ENDPOINT_HEALTH_PROBES_ENABLED=true 
ENV ENABLE_EMAIL_SERVER=false 
ENV PYTHON_URL=http://compreface-core-service:3000

ARG VERSION=dev
ARG REVISION=unknown
LABEL org.opencontainers.image.title="compreface-admin" 
LABEL org.opencontainers.image.version="${VERSION}" 
LABEL org.opencontainers.image.revision="${REVISION}" 
LABEL org.opencontainers.image.source="https://github.com/exadel-inc/CompreFace" 
LABEL org.opencontainers.image.licenses="Apache-2.0" 
LABEL org.opencontainers.image.vendor="mega (repackaged from Exadel CompreFace)"

# Install required package
RUN groupadd --system --gid 1001 appuser 
RUN useradd --system --uid 1001 --gid appuser --home-dir /app --shell /usr/sbin/nologin appuser 
RUN apt-get update && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy build result
COPY --from=builder --chown=appuser:appuser /workspace/app.jar /app/app.jar
COPY LICENSE NOTICE /usr/share/licenses/compreface/

# Cleanup Proxy
ENV http_proxy=
ENV https_proxy=
ENV no_proxy=localhost,127.0.0.1,.bankmega.com
ENV HTTP_PROXY=
ENV HTTPS_PROXY=
ENV NO_PROXY=localhost,127.0.0.1,.bankmega.com

# Define user
USER appuser

EXPOSE 8080 8081

ENTRYPOINT ["sh", "-c", "exec java $ADMIN_JAVA_OPTS -jar /app/app.jar"]
