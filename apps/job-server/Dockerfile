# Dependencies stage
FROM node:23-alpine AS deps

# Install system dependencies
RUN apk add --no-cache libc6-compat wget

# Set working directory
WORKDIR /app

# Install pnpm
RUN npm install -g pnpm

# Copy workspace configuration files
COPY pnpm-workspace.yaml ./
COPY package.json pnpm-lock.yaml ./

# Copy all package.json files to establish workspace structure
COPY packages/database/package.json ./packages/database/
COPY apps/job-server/package.json ./apps/job-server/
COPY apps/nextjs-app/package.json ./apps/nextjs-app/

# Install all dependencies with cache mount
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    --mount=type=cache,target=/app/node_modules/.pnpm \
    pnpm install --frozen-lockfile

# Database build stage
FROM deps AS database-builder

# Copy database source
COPY packages/database ./packages/database

# Build database package with cache mount
RUN --mount=type=cache,target=/app/node_modules/.pnpm \
    pnpm --filter @streamystats/database build

# Job server build stage
FROM database-builder AS job-server-builder

# Copy job-server source
COPY apps/job-server ./apps/job-server

# Build the job-server application with cache mount
RUN --mount=type=cache,target=/app/node_modules/.pnpm \
    pnpm --filter @streamystats/job-server build

# Production runtime stage
FROM node:23-alpine AS runner

# Install system dependencies
RUN apk add --no-cache libc6-compat wget

# Create a non-root user
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 jobserver

# Set working directory
WORKDIR /app

# Copy the job-server package.json and modify it for production
COPY --from=job-server-builder /app/apps/job-server/package.json ./package.json

# Replace workspace dependency with file dependency and install
RUN sed -i 's/"@streamystats\/database": "workspace:\*"/"@streamystats\/database": "file:\/app\/database"/' package.json && \
    npm install --omit=dev

# Copy built applications from build stage
COPY --from=job-server-builder --chown=jobserver:nodejs /app/apps/job-server/dist ./dist
COPY --from=job-server-builder --chown=jobserver:nodejs /app/packages/database/dist ./database/dist
COPY --from=job-server-builder --chown=jobserver:nodejs /app/packages/database/package.json ./database/package.json

# Switch to non-root user
USER jobserver

# Set environment variables
ENV NODE_ENV=production
ENV PORT=3005

# Expose port
EXPOSE 3005

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:3005/health || exit 1

# Start the application directly
CMD ["/usr/local/bin/node", "dist/index.js"] 