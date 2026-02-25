#!/bin/bash

if [ -z "$1" ]; then
  echo "Usage: $0 <pod-name>"
  exit 1
fi

POD_NAME=$1
NAMESPACE=geoserver-cloud

echo ">> Using namespace: $NAMESPACE"
echo ">> Tailing logs for pod: $POD_NAME"

kubectl logs -f "$POD_NAME" -n "$NAMESPACE"
