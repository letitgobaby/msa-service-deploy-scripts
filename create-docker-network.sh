#!/bin/bash

# 네트워크 이름 변수 설정
NETWORK_NAME=${1:-sample-net}

# 네트워크가 존재하는지 확인
docker network ls | grep -q $NETWORK_NAME

# 네트워크가 없다면 생성
if [ $? -ne 0 ]; then
  echo "Network $NETWORK_NAME does not exist. Creating it..."
  docker network create $NETWORK_NAME
else
  echo "Network $NETWORK_NAME already exists."
fi