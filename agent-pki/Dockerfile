# Build images pinned per docs/VERSIONS.md (D-005/D-006).
# Context is the REPO ROOT so delegation-common (the one home of the assertion
# type, CLAUDE.md §5) can be built alongside.
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /common
COPY delegation-common/pom.xml .
COPY delegation-common/src src
RUN mvn -q -B -DskipTests install
WORKDIR /app
COPY agent-pki/pom.xml .
RUN mvn -q -B dependency:go-offline
COPY agent-pki/src src
RUN mvn -q -B -DskipTests package

FROM eclipse-temurin:21-jre
COPY --from=build /app/target/agent-pki-*.jar /app/app.jar
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
