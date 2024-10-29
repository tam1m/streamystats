#!/bin/bash
set -e

# Verify DATABASE_URL environment variable is set
if [[ -z "${DATABASE_URL}" ]]; then
  echo "DATABASE_URL is not set. Exiting..."
  exit 1
fi

# Extract database name from DATABASE_URL
DB_NAME="${DATABASE_URL##*/}"
echo "Extracted database name: $DB_NAME"

# Check if the database already exists by attempting `mix ecto.create`
echo "Checking if database $DB_NAME exists and creating if it does not..."
if ! MIX_ENV=prod mix ecto.create; then
  echo "Database $DB_NAME already exists or could not be created."
else
  echo "Database $DB_NAME created successfully."

  echo "Running migrations..."
  MIX_ENV=prod mix ecto.migrate

  echo "Seeding the database..."
  MIX_ENV=prod mix run priv/repo/seeds.exs
fi

echo "Building the Phoenix application in production mode..."
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix compile
MIX_ENV=prod mix release

echo "Starting Phoenix server in production mode..."
exec _build/prod/rel/streamystat_server/bin/streamystat_server start
