# Keycloak with workstream B's act-spiffe protocol mapper baked in.
# Base pinned per docs/VERSIONS.md — must match keycloak.version in pom.xml.
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -q -B dependency:go-offline
COPY src src
RUN mvn -q -B -DskipTests package

FROM quay.io/keycloak/keycloak:26.6.0
COPY --from=build /app/target/keycloak-spiffe-spi-*.jar /opt/keycloak/providers/
