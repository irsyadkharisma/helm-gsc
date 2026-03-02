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
