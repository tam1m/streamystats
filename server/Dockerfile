# Use an official Elixir runtime as a parent image.
FROM elixir:latest

RUN apt-get update && \
  apt-get install -y postgresql-client curl

# Create server directory and copy the Elixir projects into it.
RUN mkdir /server
COPY . /server
WORKDIR /server

# Install Hex package manager and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Install dependencies and compile the project
RUN mix deps.get && \
    mix deps.compile

# Compile the project in production mode
ENV MIX_ENV=prod
RUN mix compile

# Build the release
RUN mix release

# Make the entrypoint script executable
RUN chmod +x /server/entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["/server/entrypoint.sh"]
