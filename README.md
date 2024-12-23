### msa-service-deploy-scripts
- 하나의 호스트에서 여러 개의 MSA 서비스를 구동하며 무중단 배포를 구현한 샘플 프로젝트

#### 이 프로젝트가 필요한 환경
```
 - 특정 상황에서(1개 호스트에서 여러개의 서비스 관리) 도커를 이용한 무중단 배포 & 스케일 아웃
```

#### 프로젝트 목표
- 서비스 중단 없이 새로운 버전을 배포하는 프로세스를 자동화하여, 운영 중 발생할 수 있는 요청 손실을 최소화
- 호스트 내에서 특정 서비스의 스케일 아웃(SCALE-OUT)을 자동화

#### 프로젝트 사용 기술
 - docker (도커설치 필수)
 - spring boot3
 - spring cloud gateway
 - spring cloud discovery (Eureka)
 - Bash Sell

#### 프로젝트 아키텍처
- sample-Eureka / 1개 port:8761
- sample-gateway / 1개 port:8080
- sample-service / n개 port:1024-65535

#### 프로젝트 구동 및 테스트
```
# 1. 유레카, 게이트웨이 도커 실행
./sample-init.sh

# 2. 서비스 배포 ./deploy.sh ('local' or 'prod')
./deploy.sh prod

# 3. 테스트 요청 실행
./request-test.sh

# 4. 새버전 배포 (간단하게 프로파일 바꿔서 실행)
./deploy.sh local

# 5. 요청 로그에서 에러 없이 리터값 바뀌는 것 확인
```

#### 결과
<img width="700" alt="Screenshot 2024-12-23 at 15 27 46" src="https://github.com/user-attachments/assets/0c6d724f-02bd-4225-a903-a75563c18167" />

- 


#### deploy.sh 실행 과정

1. **프로파일 설정 변수 읽어오기**
~~~
ENV=${1:-prod}  # Default to 'prod' if no argument is provided
CONFIG_FILE="${ENV}.env"

if [ -f "$CONFIG_FILE" ]; then
  echo "Loading configuration for '$ENV' environment..."
  source "$CONFIG_FILE"
else
  echo "Configuration file for '$ENV' environment not found. Aborting deployment."
  exit 1
fi
~~~

2. **변수 설정 및 새로운 Docker 이미지 빌드**
~~~
TIMESTAMP=$(date +%Y%m%d-%H%M)
NEW_IMAGE_TAG="${APP_NAME}:${TIMESTAMP}"
NEW_CONTAINER_NAME="${APP_NAME}-${TIMESTAMP}"

docker build -t "$NEW_IMAGE_TAG" .
if [ $? -ne 0 ]; then
  echo "Docker image build failed. Aborting deployment."
  exit 1
fi

// 새로 빌드된 이미지에 latest 태그 달아줌
docker tag "$NEW_IMAGE_TAG" "${APP_NAME}:latest"
~~~

3. **새로운 Docker 컨테이너 실행**
~~~
for i in $(seq 1 $INSTANCE_NUM); do
  NEW_CONTAINER_NAME="${APP_NAME}-${TIMESTAMP}-${i}"
  HTTP_PORT=$(find_unused_port) -- 포트 중복을 피하기 위해 랜덤포트 할당

  docker run --name "$NEW_CONTAINER_NAME" \
    --network sample-net \
    -e SERVER_PORT=$HTTP_PORT \
    -e SPRING_PROFILE=$ENV \
    -p $HTTP_PORT:$HTTP_PORT \
    -d "${APP_NAME}:latest"
done
~~~

4. **새로운 컨테이너 Health Check**
~~~
HEALTH=""
for i in {1..10}; do
  HEALTH=$(curl -s http://localhost:$HTTP_PORT/actuator/health)
  if [ "$HEALTH" == "$SUCCESS_HEALTH_CHECK" ]; then
    echo "New container $NEW_CONTAINER_NAME is healthy."
    break
  fi
  sleep 3
done
~~~

5. **Health Check 실패 처리**
~~~
if [ "$HEALTH" != "$SUCCESS_HEALTH_CHECK" ]; then
  echo "Health check failed for $NEW_CONTAINER_NAME. Stopping and removing the failed container."
  docker logs $NEW_CONTAINER_NAME > $LOG_FILE
  echo "$NEW_CONTAINER_NAME failed" >> $FAILED_LOG_FILE
fi

if [ -s $FAILED_LOG_FILE ]; then
  echo "Health check failed for one or more containers. Stopping and removing all new containers."
  while IFS= read -r line; do
    CONTAINER_NAME=$(echo $line | awk '{print $1}')
    docker stop $CONTAINER_NAME
    docker rm $CONTAINER_NAME
  done < $FAILED_LOG_FILE

  exit 1  # 배포 실패 처리
fi
~~~

6. **기존 컨테이너 종료 및 제거**
~~~
OLD_CONTAINER_NAMES=$(docker ps -a --filter "name=${APP_NAME}-" --format "{{.Names}}" | grep -v -E "$(echo ${NEW_CONTAINER_NAMES[@]} | sed 's/ /|/g')")

if [ -n "$OLD_CONTAINER_NAMES" ]; then
  docker stop $OLD_CONTAINER_NAMES
  docker rm $OLD_CONTAINER_NAMES
else
  echo "No old containers found."
fi
~~~
