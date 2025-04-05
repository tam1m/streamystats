FROM oven/bun:alpine AS base

# Install sharp dependencies
RUN apk add --no-cache libc6-compat

# Stage 1: Install dependencies
FROM base AS deps
WORKDIR /app
COPY package.json bun.lock ./

# Add sharp explicitly
RUN bun add sharp
RUN bun install --frozen-lockfile

# Stage 2: Build the application
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
# Create public directory if it doesn't exist
RUN mkdir -p public
RUN bun run build

# Stage 3: Production server
FROM base AS runner
WORKDIR /app
ENV NODE_ENV=production

# Install sharp in the production environment
RUN apk add --no-cache libc6-compat
COPY --from=deps /app/node_modules/sharp ./node_modules/sharp

# Copy the standalone output
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
RUN mkdir -p ./public
COPY --from=builder --chown=1000:1000 /app/public/. ./public/

EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

CMD ["bun", "run", "server.js"]