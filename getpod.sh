#!/bin/bash
# Watch GeoServer pods status in geoserver-fix namespace

#NS=${NS:-default}
NS=geoserver-cloud

echo ">> Using namespace: $NS"
INTERVAL=2

echo ">> Watching pods in namespace: $NS (refresh every $INTERVAL sec)"
watch -n $INTERVAL "kubectl get pods -n $NS"

