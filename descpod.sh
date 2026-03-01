
#!/bin/bash
# Simple wrapper for kubectl describe in geoserver-fix namespace

if [ -z "$1" ]; then
  echo "Usage: $0 <pod-name>"
  exit 1
fi

POD_NAME=$1
NAMESPACE="geoserver-cloud"

echo ">> Describing pod: $POD_NAME (namespace: $NAMESPACE)"
kubectl describe pod  "$POD_NAME" -n "$NAMESPACE"
