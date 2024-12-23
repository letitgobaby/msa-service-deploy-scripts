#!/bin/bash

# Environment Variables
ENV=${1:-prod} # Default to 'prod' if no argument is provided
CONFIG_FILE="${ENV}.env"

# Load Environment Configurations
if [ -f "$CONFIG_FILE" ]; then
  echo "Loading configuration for '$ENV' environment..."
  source "$CONFIG_FILE"
else
  echo "Configuration file for '$ENV' environment not found. Aborting deployment."
  exit 1
fi

# Variables
TIMESTAMP=$(date +%Y%m%d-%H%M)
NEW_IMAGE_TAG="${APP_NAME}:${TIMESTAMP}"
NEW_CONTAINER_NAME="${APP_NAME}-${TIMESTAMP}"

# Functions
find_unused_port() {
  local excluded_ports=${EXCLUDED_PORTS:-"8080"} # 기본값 설정
  local port_list=$(echo "$excluded_ports" | tr ',' ' ') # 콤마를 공백으로 변환
  while :; do
    PORT=$(shuf -i 1024-65535 -n 1)
    if ! echo "$port_list" | grep -wq "$PORT" && ! lsof -i :$PORT > /dev/null; then
      echo $PORT
      return
    fi
  done
}

# Step 1: Build Docker Image
echo "Building Docker image..."
docker build -t "$NEW_IMAGE_TAG" .
if [ $? -ne 0 ]; then
  echo "Docker image build failed. Aborting deployment."
  exit 1
fi

echo "Tagging image as latest..."
docker tag "$NEW_IMAGE_TAG" "${APP_NAME}:latest"

# Step 2: Start New Containers
echo "Finding available ports..."
INSTANCE_NUM=${INSTANCE_NUM:-1} # Default to 1 instances
NEW_CONTAINER_NAMES=()  # 배열로 컨테이너 이름들 저장

for i in $(seq 1 $INSTANCE_NUM); do
  # Set the container name dynamically
  NEW_CONTAINER_NAME="${APP_NAME}-${TIMESTAMP}-${i}"
  HTTP_PORT=$(find_unused_port)

  echo "Starting new container $NEW_CONTAINER_NAME..."
  echo "Available ports - HTTP: $HTTP_PORT"

  # Run the container with different ports for each instance
  docker run --name "$NEW_CONTAINER_NAME" \
    --network sample-net \
    -e SERVER_PORT=$HTTP_PORT \
    -e SPRING_PROFILE=$ENV \
    -p $HTTP_PORT:$HTTP_PORT \
    -d "${APP_NAME}:latest"

  if [ $? -ne 0 ]; then
    echo "Failed to start new container $NEW_CONTAINER_NAME. Aborting deployment."
    exit 1
  fi

  # 컨테이너 이름을 배열에 추가
  NEW_CONTAINER_NAMES+=("$NEW_CONTAINER_NAME")
done

# Step 3: Health Check
echo "Performing health check..."
SUCCESS_HEALTH_CHECK='{"status":"UP"}' # 성공 메시지
FAILED_LOG_FILE="logs/failed_containers.log" # 로그 파일 설정
mkdir -p logs  # logs 디렉토리 없으면 생성
> $FAILED_LOG_FILE  # 실패 로그 파일 초기화

# Health check for each new container in parallel
for NEW_CONTAINER_NAME in "${NEW_CONTAINER_NAMES[@]}"; do
  {
    HEALTH=""
    for i in {1..10}; do
      HEALTH=$(curl -s http://localhost:$HTTP_PORT/actuator/health)
      if [ "$HEALTH" == "$SUCCESS_HEALTH_CHECK" ]; then
        echo "New container $NEW_CONTAINER_NAME is healthy."
        break
      fi
      echo "Health check attempt $i for $NEW_CONTAINER_NAME failed. Retrying..."
      sleep 3
    done

    # If health check failed after retries
    if [ "$HEALTH" != "$SUCCESS_HEALTH_CHECK" ]; then
      echo "Health check failed for $NEW_CONTAINER_NAME. Stopping and removing the failed container."

      # 로그 파일 저장
      LOG_FILE="logs/deploy_failed_${NEW_CONTAINER_NAME}.log"
      echo "Saving logs of failed container $NEW_CONTAINER_NAME to $LOG_FILE"
      
      # 실패한 컨테이너의 로그를 파일로 저장
      docker logs $NEW_CONTAINER_NAME > $LOG_FILE

      # 실패한 컨테이너를 실패 로그에 기록
      echo "$NEW_CONTAINER_NAME failed" >> $FAILED_LOG_FILE
    fi
  } &
done

# Wait for all health check processes to finish
wait

# Health check 후 실패한 컨테이너가 있는지 확인
if [ -s $FAILED_LOG_FILE ]; then
  echo "Health check failed for one or more containers. Stopping and removing all new containers."
  while IFS= read -r line; do
    CONTAINER_NAME=$(echo $line | awk '{print $1}')
    docker stop $CONTAINER_NAME
    docker rm $CONTAINER_NAME
  done < $FAILED_LOG_FILE

  exit 1  # 배포 실패 처리
else
  echo "All containers passed the health check. Deployment successful."
fi

# 새로운 컨테이너가 정상적으로 실행되었는지 확인하기 위해 잠시 대기
# 서비스 디스커버리에 등록되는 시간을 고려하여 60초 대기
echo "Waiting for service discovery to register the new instances..."
sleep 60

# Step 4: Stop and Remove Old Containers (Exclude new containers)
echo "Stopping and removing old containers..."

# 현재 실행 중인 모든 컨테이너 목록을 가져오고 새로 생성된 컨테이너는 제외합니다.
OLD_CONTAINER_NAMES=$(docker ps -a --filter "name=${APP_NAME}-" --format "{{.Names}}" | grep -v -E "$(echo ${NEW_CONTAINER_NAMES[@]} | sed 's/ /|/g')")

if [ -n "$OLD_CONTAINER_NAMES" ]; then
  echo "Stopping and removing old containers: $OLD_CONTAINER_NAMES"
  docker stop $OLD_CONTAINER_NAMES
  docker rm $OLD_CONTAINER_NAMES
else
  echo "No old containers found."
fi


# Completion
echo "New containers: ${NEW_CONTAINER_NAMES[@]}"
echo "Deployment for '$ENV' environment completed successfully!"
