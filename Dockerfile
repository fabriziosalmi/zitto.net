# Use the official Elixir image as base
FROM elixir:1.18.4-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    nodejs \
    npm \
    curl \
    ca-certificates \
    && rm -rf /var/cache/apk/*

# Set build ENV
ENV MIX_ENV=prod

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Create app directory
WORKDIR /app

# Copy mix files
COPY mix.exs mix.lock ./

# Install dependencies
RUN mix deps.get --only prod && \
    mix deps.compile

# Copy assets
COPY assets assets

# Copy priv
COPY priv priv

# Copy source code
COPY lib lib

# Copy config
COPY config config

# Build assets
RUN mix assets.deploy

# Compile the release
RUN mix compile

# Build the release
RUN mix release

# Start a new build stage for the runtime image
FROM alpine:3.20 AS runtime

# Install runtime dependencies
RUN apk add --no-cache \
    libstdc++ \
    openssl \
    ncurses-libs \
    curl \
    ca-certificates \
    tini \
    && rm -rf /var/cache/apk/*

# Create app user with specific UID/GID and no shell
RUN addgroup -g 1000 -S phoenix && \
    adduser -u 1000 -S phoenix -G phoenix -s /sbin/nologin

# Create app directory
WORKDIR /app

# Change ownership
RUN chown phoenix:phoenix /app

# Switch to phoenix user
USER phoenix

# Copy the release from builder stage
COPY --from=builder --chown=phoenix:phoenix /app/_build/prod/rel/the_collective ./

# Create directories for logs and tmp with proper permissions
RUN mkdir -p /tmp /app/log && \
    chmod 750 /app/log

# Expose port
EXPOSE 4000

# Set environment variables
ENV HOME=/app \
    MIX_ENV=prod \
    LANG=C.UTF-8

# Remove default SECRET_KEY_BASE to force proper configuration
# ENV SECRET_KEY_BASE must be provided at runtime

# Health check using the built-in health endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:4000/health/live || exit 1

# Use tini as init system for proper signal handling
ENTRYPOINT ["/sbin/tini", "--"]

# Start the application
CMD ["./bin/the_collective", "start"]
