#!/bin/bash

for i in {1..300}; do
    echo "$(date '+%Y-%m-%d %H:%M:%S') - No.${i} - $(curl -s http://localhost:8080/sample-service/profile)"
    sleep 0.5
done

