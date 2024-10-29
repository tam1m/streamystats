#!/bin/bash

# Extract database name from DATABASE_URL
DB_NAME="${DATABASE_URL##*/}"
echo "Extracted database name: $DB_NAME"

# Verify connection and check if database exists
echo "Checking if database $DB_NAME exists..."
if ! psql -Atqc "\\list $DB_NAME" > /dev/null 2>&1; then
  echo "Database $DB_NAME does not exist. Creating..."
  createdb -E UTF8 "$DB_NAME" -l en_US.UTF-8 -T template0
  
  echo "Running migrations..."
  MIX_ENV=prod mix ecto.migrate
  
  echo "Seeding the database..."
  MIX_ENV=prod mix run priv/repo/seeds.exs
  
  echo "Database $DB_NAME created and initialized."
else
  echo "Database $DB_NAME already exists. Skipping creation and migrations."
fi

echo "Building the Phoenix application in production mode..."
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix compile
MIX_ENV=prod mix release

echo "Starting Phoenix server in production mode..."
_build/prod/rel/streamystat_server/bin/streamystat_server start