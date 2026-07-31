# Build images pinned per docs/VERSIONS.md (D-005/D-006; node pin D-024).
# Build context is the REPO ROOT (compose: context .., dockerfile
# agent-client/Dockerfile) so the console is built in-image — a fresh machine
# needs no Node (D-024 supersedes D-017's host-build). For fast UI iteration,
# infra/docker-compose.dev.yml mounts a host-built dist over the baked one.
FROM node:22.23.2-alpine AS console-build
WORKDIR /console
COPY console/package.json console/package-lock.json ./
RUN npm ci
COPY console/ .
RUN npm run build

FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY agent-client/pom.xml .
RUN mvn -q -B dependency:go-offline
COPY agent-client/src src
RUN mvn -q -B -DskipTests package

FROM eclipse-temurin:21-jre
COPY --from=build /app/target/agent-client-*.jar /app/app.jar
COPY --from=console-build /console/dist/console/browser /app/console-ui
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
