FROM arm64v8/openjdk:17-ea-jdk-slim

WORKDIR /app

COPY ./service/build/libs/*.jar /app/app.jar

# Default environment variable
ENV SPRING_PROFILE=local

ENTRYPOINT ["java", "-jar", "-Dspring.profiles.active=${SPRING_PROFILE}", "/app/app.jar"]