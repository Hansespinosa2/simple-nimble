# Simple Nimble

## Local development

The app uses PostgreSQL in development, test, and production. To start a local database with Docker Compose:

```sh
export POSTGRES_PASSWORD=local-dev-only-password
docker compose up -d db
bundle install
bin/rails db:prepare
bin/dev
```

The database listens only on `127.0.0.1`. The test suite uses a separate `simple_nimble_test` database and can be run with:

```sh
bin/rails db:test:prepare test test:system
```

Connection settings can be overridden with `DB_HOST`, `DB_PORT`, `POSTGRES_USER`, and `POSTGRES_PASSWORD`. `POSTGRES_USER` defaults to `postgres` and `DB_HOST` defaults to `localhost`.

## Internal Kamal deployment

`config/deploy.yml` defines a PostgreSQL 17 accessory named `db`. It keeps its data in a persistent Docker volume on the configured server and does not publish a database port. The app connects over Kamal's internal Docker network.

Set a strong `POSTGRES_PASSWORD` in the deployment environment before running Kamal. Update the example server IP, public host, and image registry in `config/deploy.yml` for the team server.

An existing SQLite database is not imported automatically. Export and import any records that need to be retained before switching a server that already contains data.
