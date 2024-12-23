FROM arm64v8/openjdk:17-ea-jdk-slim

WORKDIR /app

COPY ./build/libs/*.jar /app/app.jar

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]