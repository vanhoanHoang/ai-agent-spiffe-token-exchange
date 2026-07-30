# Build images pinned per docs/VERSIONS.md (D-005)
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -q -B dependency:go-offline
COPY src src
RUN mvn -q -B -DskipTests package

FROM eclipse-temurin:21-jre
COPY --from=build /app/target/mcp-server-*.jar /app/app.jar
EXPOSE 8443
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
