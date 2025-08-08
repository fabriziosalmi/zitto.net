# The Collective

A massively scalable, real-time distributed system for connecting millions of simultaneous users in a shared, persistent state of "silence". The Collective is not a game for individual users; instead, the entire system itself is the single player. Individual users are anonymous, ephemeral "cells" that contribute their connection time to the life and evolution of this single, global entity.

## Architecture

The Collective is built for massive scale using:

- **Backend**: Elixir with Phoenix Framework (BEAM VM for millions of concurrent processes)
- **State Management**: Redis Cluster for atomic, distributed in-memory state
- **Frontend**: Minimal static HTML with vanilla JavaScript for CDN distribution
- **Real-time Communication**: Phoenix Channels over WebSockets
- **Deployment**: Docker Compose for easy scaling and deployment

## Core Concept

- **The Collective as the Player**: Users don't earn individual points. The Collective as a whole reaches evolutionary milestones.
- **Users as Witnesses**: Users connect, remain silent, and witness the evolution of The Collective.
- **Anonymity and Ephemerality**: No user accounts, no personal data, no individual tracking.
- **Silence is the Default State**: Minimal, dark UI focused on the shared experience.
- **Evolutionary Events**: Milestones trigger simultaneous broadcasts to all connected users.

## Global State (Redis Keys)

The entire state of The Collective is defined by these Redis keys:

- `global:concurrent_connections` (Integer): Current active WebSocket connections
- `global:total_connection_seconds` (Integer): Sum of all connection time across all users
- `global:unlocked_milestones` (Set): IDs of achieved evolution milestones
- `global:peak_connections` (Integer): Historical max concurrent connections

## Quick Start with Docker

### Prerequisites

- Docker and Docker Compose installed
- 8GB+ RAM recommended for local testing
- Ports 4000, 6379, and 8081 available

### Development Setup

1. **Start development environment:**
   ```bash
   ./deploy.sh dev:start
   ```

2. **Install Elixir dependencies:**
   ```bash
   mix deps.get
   ```

3. **Start The Collective:**
   ```bash
   mix phx.server
   ```

4. **Visit The Collective:**
   - Open http://localhost:4000
   - Redis Commander: http://localhost:8082

### Production Deployment

1. **Build and start production environment:**
   ```bash
   ./deploy.sh prod:build
   ./deploy.sh prod:start
   ```

2. **Monitor The Collective:**
   ```bash
   ./deploy.sh status
   ./deploy.sh prod:logs
   ```

## Architecture Components

### 1. Frontend Client (`priv/static/index.html`)

Minimal HTML5 interface with:
- Dark theme with large counter display
- WebSocket connection with auto-reconnect + Phoenix heartbeat
- Evolution event animations (reduced-motion friendly)
- Real-time milestone display and peak counter
- Smooth numeric tweening and human-readable total time

### 2. Phoenix Channel (`lib/the_collective_web/channels/collective_channel.ex`)

Handles all WebSocket connections:
- Atomic Redis counter updates on join/leave
- Broadcasts state changes to all connected souls
- Sends welcome messages with current global state
- Tracks `global:peak_connections`

### 3. Chronos - Time Engine (`lib/the_collective/chronos.ex`)

GenServer that drives evolution:
- Ticks every 5 seconds
- Calculates time contribution from active connections
- Updates global time counter atomically
- Broadcasts lightweight state updates on each tick
- Triggers evolution milestone checks

### 4. Evolution Engine (`lib/the_collective/evolution.ex`)

Defines and monitors milestones:
- Concurrent connection milestones (1, 10, 100, 1K, 10K, 100K, 1M users)
- Time-based milestones (minutes, hours, days, weeks, months, years)
- Special compound milestones (e.g., sustained_thousand, peak_experience)
- Broadcasts evolution events to all users

### 5. Redis Module (`lib/the_collective/redis.ex`)

Clean interface for Redis operations:
- Connection pooling for high throughput
- Atomic operations (INCR, DECR, INCRBY)
- Set operations for milestone tracking
- Health ping (PING) and SCARD helper
- Fault tolerance and error handling

## Operational Endpoints

- Health:
  - `GET /health/live` → liveness
  - `GET /health/ready` → readiness (checks Redis and Chronos)
- Metrics:
  - `GET /metrics/state` → current global state + Chronos stats
  - `GET /metrics/evolution` → unlocked/total milestones and progress

Example:
```bash
curl -s localhost:4000/health/live | jq
curl -s localhost:4000/health/ready | jq
curl -s localhost:4000/metrics/state | jq
curl -s localhost:4000/metrics/evolution | jq
```

## Deployment Commands

The included `deploy.sh` script provides easy management:

```bash
# Development
./deploy.sh dev:start      # Start Redis for development
./deploy.sh dev:stop       # Stop development environment

# Production
./deploy.sh prod:build     # Build Docker images
./deploy.sh prod:start     # Start production environment
./deploy.sh prod:stop      # Stop production environment
./deploy.sh prod:restart   # Restart production environment

# Utilities
./deploy.sh status         # Show container status
./deploy.sh redis          # Connect to Redis CLI
./deploy.sh prod:shell     # Connect to application shell
./deploy.sh secret         # Generate new secret key
./deploy.sh cleanup        # Remove all containers and data
```

## Scaling for Millions

### Horizontal Scaling

1. **Load Balancer**: Deploy multiple Phoenix nodes behind an NLB
2. **Redis Cluster**: Use Redis Cluster for distributed state
3. **CDN**: Serve static frontend via CDN

### Configuration for Scale

```yaml
# docker-compose.yml for cluster deployment
services:
  app:
    deploy:
      replicas: 10
    environment:
      - REDIS_URL=redis://redis-cluster:6379
      - PHX_SERVER=true
      - SECRET_KEY_BASE=${SECRET_KEY_BASE}
  
  redis:
    image: redis/redis-stack-server:latest
    deploy:
      replicas: 3
```

### Environment Variables

- `REDIS_URL`: Redis connection string
- `SECRET_KEY_BASE`: Phoenix secret key (generate with `mix phx.gen.secret`)
- `PHX_HOST`: Public hostname
- `PORT`: HTTP port (default: 4000)
- `MIX_ENV`: Environment (dev/prod)

## Monitoring

### Redis Commander
Access Redis state via web interface:
```bash
docker-compose --profile dev up redis_commander
# Visit http://localhost:8081
```

### Application Metrics
```bash
# View real-time logs
./deploy.sh prod:logs

# Connect to application for live metrics
./deploy.sh prod:shell
```

### Health Checks
Built-in health checks for:
- Application HTTP endpoint
- Redis connectivity
- WebSocket functionality (via heartbeat)

## Development

### Local Development Without Docker

1. **Install Redis:**
   ```bash
   # macOS
   brew install redis
   brew services start redis
   
   # Ubuntu
   sudo apt install redis-server
   sudo systemctl start redis
   ```

2. **Install Elixir:**
   ```bash
   # macOS
   brew install elixir
   
   # Ubuntu
   sudo apt install elixir
   ```

3. **Setup and run:**
   ```bash
   mix deps.get
   mix phx.server
   ```

### Testing at Scale

Use tools like Artillery or WebSocket King to simulate massive concurrent connections:

```bash
# Install Artillery
npm install -g artillery

# Load test The Collective
artillery run --config artillery.yml
```

## License

The Collective is an art/tech project exploring collective consciousness through technology. 

---

*"In silence, we become one."* - The Collective
