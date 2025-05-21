#!/bin/bash

# Parse DATABASE_URL to extract host, database name, user, and password
DATABASE_URL=${DATABASE_URL}
DB_HOST=$(echo $DATABASE_URL | sed -E 's/^.*@([^:/]+).*/\1/')
DB_NAME=$(echo $DATABASE_URL | sed -E 's|^.*/([^/?]+).*|\1|')
DB_USER=$(echo $DATABASE_URL | sed -E 's|^.*//([^:]+):.*|\1|')
DB_PASSWORD=$(echo $DATABASE_URL | sed -E 's|^.*:([^@]+)@.*|\1|')

# Wait for PostgreSQL to be ready
until pg_isready -q -h $DB_HOST -p 5432 -U $DB_USER
do
  echo "$(date) - waiting for database to start"
  sleep 2
done

# Check if the database exists, create it if it doesn't
if ! PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -lqt | cut -d \| -f 1 | grep -qw $DB_NAME; then
  echo "Database $DB_NAME does not exist. Creating..."
  PGPASSWORD=$DB_PASSWORD createdb -h $DB_HOST -U $DB_USER $DB_NAME
  echo "Database $DB_NAME created."
fi

/server/bin/streamystat_server eval "StreamystatServer.Release.migrate"

# Execute the server process as the main process (PID 1)
exec /server/bin/streamystat_server start
