FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml ./
COPY contracts contracts
COPY rules-service rules-service
COPY posting-service posting-service
COPY ui-service ui-service
COPY gateway gateway
ARG SERVICE
RUN mvn -B -ntp -pl "$SERVICE" -am package -DskipTests
RUN cp "$SERVICE"/target/"$SERVICE"-0.1.0-SNAPSHOT.jar /app.jar

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build --chown=10001:10001 /app.jar /app/app.jar
USER 10001
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=70", "-jar", "/app/app.jar"]
