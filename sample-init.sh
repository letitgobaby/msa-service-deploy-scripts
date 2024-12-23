#!/bin/bash

# Step 1. 샘플 네트워크 생성
# 이 프로젝트에서는 샘플 서비스를 실행하기 위해 sample-net이라는 이름의 Docker 네트워크를 생성합니다.
./create-docker-network.sh sample-net


# Step 2. 샘플 Eurkea 서버 실행
# discovery 폴더에 있는 spring 프로젝트를 빌드 후 실행합니다.
cd discovery
./gradlew clean build bootJar
docker build -t discovery:latest .
docker run -d --name sample-eureka --network sample-net -p 8761:8761 discovery:latest
cd ..


# Step 3. 샘플 Gateway 서버 실행
# gateway 폴더에 있는 spring 프로젝트를 빌드 후 실행합니다.
cd gateway
./gradlew clean build bootJar
docker build -t gateway:latest .
docker run -d --name sample-gateway --network sample-net -p 8080:8080 gateway:latest
cd ..

# Step 4. 샘플 서비스 jar 파일 준비
cd service
./gradlew clean bootJar
cd ..

# Step 5. deploy.sh 직접 실행
# ./deploy.sh prod
