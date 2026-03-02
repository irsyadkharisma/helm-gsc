# Helm chart for GeoServer-Cloud

A Helm chart for GeoServer-Cloud

## include this chart as dependency of your own chart:

This chart is intended to be used as a dependency in a "umbrella chart". To use it, include the following section in your `Chart.yaml`:

```yaml
dependencies:
  - name: geoservercloud
    repository: https://camptocamp.github.io/helm-geoserver-cloud
    version: <version-numer-here>
```

See the value file for configuration options. A good starting points are the [Examples](examples/README.md)

## Developing on geoserver-cloud code using this chart

To develop in this chart, we recommend that you use `k3d` if you want to use your machine.
Also, depending on the use case, you will need a database or a shared folder which will be used by the pods. At any case, start following the [Examples](examples/README.md) !

## Contributing

Install the pre-commit hooks:

```bash
pip install pre-commit
pre-commit install --allow-missing-config
```
# helm-gsc

## Step-by-Step Runbook (k3s/Proxmox -> Production Style)

This section documents a repeatable deployment flow for:
- GeoServer Cloud on Kubernetes
- RabbitMQ (Bitnami chart)
- PostgreSQL (Bitnami chart)
- `jdbcconfig` profile (instead of `datadir`)
- Traefik ingress + TLS secret

### 0) Prerequisites

- Kubernetes context points to the correct cluster
- Namespace exists (or create it)
- Helm repo added

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl create namespace geoserver-cloud --dry-run=client -o yaml | kubectl apply -f -
helm repo add camptocamp https://camptocamp.github.io/helm-geoserver-cloud
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

### 1) Install RabbitMQ (Bitnami)

Create `rabbit-values.yaml`:

```yaml
auth:
  username: geoserver
  password: "sodAgemb7r4$"
  vhost: /

service:
  type: ClusterIP

resources:
  requests:
    cpu: "250m"
    memory: "256Mi"
  limits:
    cpu: "1"
    memory: "1Gi"

persistence:
  enabled: true
  size: 5Gi
  storageClass: local-path

metrics:
  enabled: true
```

Install:

```bash
helm upgrade --install rmq bitnami/rabbitmq \
  -n geoserver-cloud \
  -f rabbit-values.yaml \
  --set global.security.allowInsecureImages=true \
  --set image.registry=docker.io \
  --set image.repository=bitnamilegacy/rabbitmq \
  --set image.tag=4.1.3-debian-12-r0
```

Verify:

```bash
kubectl get pods -n geoserver-cloud | grep rmq-rabbitmq
kubectl get svc -n geoserver-cloud | grep rmq-rabbitmq
```

### 2) Install PostgreSQL (Bitnami)

Create `postgres-values.yaml`:

```yaml
auth:
  postgresPassword: "postgres123"
  username: "geoserver"
  password: "geoserver123"
  database: "geoserver"

primary:
  persistence:
    enabled: true
    storageClass: local-path
    size: 20Gi
  resources:
    requests:
      cpu: "250m"
      memory: "512Mi"
    limits:
      cpu: "1"
      memory: "1Gi"
```

Install:

```bash
helm upgrade --install pg bitnami/postgresql \
  -n geoserver-cloud \
  -f postgres-values.yaml
```

#### PostgreSQL credentials from Secret (`existingSecret`)

For production-style deployments, keep passwords in a Kubernetes Secret and reference it from `postgres-values.yaml`.

Create Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: pg-auth
  namespace: geoserver-cloud
type: Opaque
stringData:
  postgres-password: postgres123
  password: geoserver123
```

```bash
kubectl apply -f pg-auth-secret.yaml
```

Use Secret in `postgres-values.yaml`:

```yaml
auth:
  username: "geoserver"
  database: "geoserver"
  existingSecret: "pg-auth"
  secretKeys:
    adminPasswordKey: "postgres-password"
    userPasswordKey: "password"
```

Why `username` and `database` are still in values:
- `existingSecret` only provides password fields.
- PostgreSQL chart still needs `auth.username` and `auth.database` to create/use the DB user and database names.
- Keep passwords in Secret; keep non-sensitive names in values.

Verify:

```bash
kubectl get pods -n geoserver-cloud | grep pg-postgresql
kubectl get svc -n geoserver-cloud | grep pg-postgresql
```

### 3) Create JDBC schema (required)

`jdbcconfig` needs schema available in DB.

```bash
kubectl exec -it -n geoserver-cloud pg-postgresql-0 -- \
  psql -U geoserver -d geoserver -c "CREATE SCHEMA IF NOT EXISTS pgconfig AUTHORIZATION geoserver;"
```

### 4) Create JDBC secret for GeoServer

Secret name below must match the name referenced in your GeoServer values.

```bash
kubectl create secret generic gs-cloud-jdbc-db -n geoserver-cloud \
  --from-literal=hostname=pg-postgresql.geoserver-cloud.svc.cluster.local \
  --from-literal=port=5432 \
  --from-literal=database=geoserver \
  --from-literal=schema=pgconfig \
  --from-literal=username=geoserver \
  --from-literal=password='geoserver123'
```

### 5) Configure GeoServer values for `jdbcconfig`

In `values.yaml`:
- set `SPRING_PROFILES_ACTIVE` to `standalone,jdbcconfig,kube`
- set Rabbit host to `rmq-rabbitmq.geoserver-cloud.svc.cluster.local` (or short name `rmq-rabbitmq`)
- include `JDBCCONFIG_*` env from secret `gs-cloud-jdbc-db`

Example env keys:
- `JDBCCONFIG_HOST`
- `JDBCCONFIG_PORT`
- `JDBCCONFIG_DATABASE`
- `JDBCCONFIG_SCHEMA`
- `JDBCCONFIG_USERNAME`
- `JDBCCONFIG_PASSWORD`

### 6) Deploy / Redeploy GeoServer Cloud

```bash
helm upgrade --install gsc camptocamp/geoservercloud \
  -n geoserver-cloud \
  -f values.yaml
```

Verify:

```bash
kubectl get pods -n geoserver-cloud
kubectl logs -n geoserver-cloud deploy/gsc-gsc-rest --tail=120 | grep -Ei "rabbit|amqp|jdbc|error|exception"
```

### 7) TLS secret + Traefik ingress (HTTPS)

If using Cloudflare Origin cert files (`origin.pem`, `origin.key`):

```bash
kubectl create secret tls geoservercloud-tls \
  -n geoserver-cloud \
  --cert=origin.pem \
  --key=origin.key \
  --dry-run=client -o yaml | kubectl apply -f -
```

Apply ingress (example file `gsc-ingress.yaml`):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gsc-gateway
  namespace: geoserver-cloud
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - geovm.wri-indonesia.id
      secretName: geoservercloud-tls
  rules:
    - host: geovm.wri-indonesia.id
      http:
        paths:
          - path: /geoserver-cloud
            pathType: Prefix
            backend:
              service:
                name: gsc-gsc-gateway
                port:
                  number: 8080
```

```bash
kubectl apply -f gsc-ingress.yaml
```

Test:

```bash
curl -vk --resolve geovm.wri-indonesia.id:443:10.10.10.15 \
  https://geovm.wri-indonesia.id/geoserver-cloud/web/
```

### 8) Common failure checklist

- `unknown anchor referenced` in Helm values:
  - anchor defined after reference, or typo in anchor name
- `secret "gs-cloud-jdbc-db" not found`:
  - create secret in `geoserver-cloud` namespace
- Rabbit `UnknownHostException`:
  - wrong `RABBITMQ_HOST`; use `rmq-rabbitmq` service name
- Rabbit `spring.rabbitmq.port` parse error (`tcp://...`):
  - do not point to non-existing service names that trigger wrong env assumptions
- PostgreSQL schema missing:
  - run `CREATE SCHEMA pgconfig` manually

# Variable Templates (Secrets)

This folder contains templates for Kubernetes Secrets and values snippets.

## Files

- `01-geoservercloud-tls-secret.yaml`:
  Traefik TLS secret (`kubernetes.io/tls`) with `tls.crt` and `tls.key`.
- `02-rabbitmq-secret.yaml`:
  GeoServer RabbitMQ connection secret (`host`, `port`, `username`, `password`, `vhost`).
- `03-postgres-auth-secret.yaml`:
  PostgreSQL Helm auth secret (`postgres-password`, `password`) for `auth.existingSecret`.
- `04-jdbc-db-secret.yaml`:
  GeoServer JDBC config secret (`hostname`, `port`, `database`, `schema`, `username`, `password`).
- `05-geoserver-admin-secret.yaml`:
  Optional emergency environment-admin credentials.
- `values-secrets-reference.yaml`:
  Example of how to reference these secrets from GeoServer values.

## Usage

1. Copy and edit values in these files.
2. Apply secrets:
   `kubectl apply -f <file>.yaml`
3. Deploy Helm release with values that reference secret keys.

