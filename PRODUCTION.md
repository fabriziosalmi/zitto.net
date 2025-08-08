# Production Deployment Guide for The Collective

This guide covers deploying The Collective at massive scale for millions of concurrent connections.

## Prerequisites

- Docker and Docker Compose
- Load balancer (AWS NLB, Cloudflare, etc.)
- Redis Cluster for high availability
- CDN for static assets

## Environment Variables

Create a `.env` file:

```bash
# Redis Configuration
REDIS_URL=redis://your-redis-cluster:6379

# Phoenix Configuration
SECRET_KEY_BASE=$(mix phx.gen.secret)
PHX_HOST=your-domain.com
PORT=4000
PHX_SERVER=true
MIX_ENV=prod

# Optional: Multi-node deployment
DNS_CLUSTER_QUERY=the-collective.internal
```

## Scaling Configuration

### For 1 Million Concurrent Connections

```yaml
# docker-compose.prod.yml
version: '3.8'

services:
  app:
    image: the_collective:latest
    deploy:
      replicas: 20
      resources:
        limits:
          cpus: '2'
          memory: 4G
        reservations:
          cpus: '1'
          memory: 2G
    environment:
      - REDIS_URL=redis://redis-cluster:6379
      - SECRET_KEY_BASE=${SECRET_KEY_BASE}
      - PHX_HOST=${PHX_HOST}
      - PHX_SERVER=true
      - MIX_ENV=prod
    ports:
      - "4000-4019:4000"
    depends_on:
      - redis
    networks:
      - collective_network

  redis:
    image: redis/redis-stack-server:latest
    deploy:
      replicas: 3
    volumes:
      - redis_cluster_data:/data
    command: >
      redis-server 
      --appendonly yes 
      --maxmemory 8gb 
      --maxmemory-policy allkeys-lru
      --tcp-keepalive 60
      --timeout 0
    networks:
      - collective_network

  load_balancer:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./ssl:/etc/ssl
    depends_on:
      - app
    networks:
      - collective_network
```

### Nginx Load Balancer Configuration

```nginx
# nginx.conf
upstream collective_backend {
    least_conn;
    server app_1:4000;
    server app_2:4000;
    # ... up to app_20:4000
}

map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}

server {
    listen 80;
    listen 443 ssl http2;
    server_name your-domain.com;

    # SSL configuration
    ssl_certificate /etc/ssl/cert.pem;
    ssl_certificate_key /etc/ssl/key.pem;

    # WebSocket support
    location /socket {
        proxy_pass http://collective_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # Static assets (serve from CDN in production)
    location / {
        proxy_pass http://collective_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Deployment Steps

### 1. Build Production Images

```bash
./deploy.sh prod:build
```

### 2. Configure Environment

```bash
# Generate secret
./deploy.sh secret

# Set environment variables
export SECRET_KEY_BASE="your_generated_secret"
export PHX_HOST="your-domain.com"
export REDIS_URL="redis://your-redis-cluster:6379"
```

### 3. Deploy

```bash
./deploy.sh prod:start
```

### 4. Monitor

```bash
# Check status
./deploy.sh status

# View logs
./deploy.sh prod:logs

# Connect to application shell
./deploy.sh prod:shell
```

## Performance Optimizations

### BEAM VM Settings

Add to your Dockerfile or environment:

```bash
# Increase BEAM scheduler count
export ERL_MAX_PORTS=4194304
export ERL_PROCESS_LIMIT=134217728

# Optimize memory
export ERL_FLAGS="+A 64 +K true +P 134217728"
```

### Redis Optimization

```redis
# redis.conf optimizations for The Collective
maxmemory 16gb
maxmemory-policy allkeys-lru
save 900 1
tcp-keepalive 60
timeout 0

# For high connection count
tcp-backlog 65535
```

### OS-Level Optimizations

```bash
# Increase file descriptor limits
echo "* soft nofile 1048576" >> /etc/security/limits.conf
echo "* hard nofile 1048576" >> /etc/security/limits.conf

# Network optimizations
echo "net.core.somaxconn = 65535" >> /etc/sysctl.conf
echo "net.ipv4.tcp_max_syn_backlog = 65535" >> /etc/sysctl.conf
```

## Monitoring

### Health Checks

The application includes built-in health checks:

- HTTP: `GET /` returns 200 if healthy
- Redis: Automatic connection monitoring
- WebSocket: Connection count tracking

### Metrics to Monitor

1. **Concurrent Connections**: `global:concurrent_connections`
2. **Total Experience Time**: `global:total_connection_seconds`
3. **Evolution Events**: `global:unlocked_milestones`
4. **Memory Usage**: Per container and Redis
5. **CPU Usage**: BEAM scheduler utilization
6. **Network**: WebSocket throughput

### Observability Stack

```yaml
# Add to docker-compose.yml
  prometheus:
    image: prom/prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml

  grafana:
    image: grafana/grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=collective
```

## Scaling Strategies

### Horizontal Scaling

1. **Add More App Instances**: Scale the `app` service replicas
2. **Redis Cluster**: Use Redis Cluster for distributed state
3. **Geographic Distribution**: Deploy in multiple regions
4. **CDN Integration**: Serve static assets from CDN

### Vertical Scaling

1. **Increase Memory**: More RAM for BEAM processes
2. **CPU Cores**: More schedulers for BEAM VM
3. **Network Bandwidth**: Higher throughput connections

## Disaster Recovery

### Backup Strategy

```bash
# Redis backup
docker exec redis redis-cli BGSAVE

# Configuration backup
tar -czf collective-config.tar.gz docker-compose.yml .env nginx.conf
```

### Recovery Procedures

```bash
# Restore Redis data
docker cp backup.rdb redis:/data/dump.rdb
docker restart redis

# Restart The Collective
./deploy.sh prod:restart
```

## Security Considerations

1. **Use TLS/SSL**: Encrypt all WebSocket connections
2. **Rate Limiting**: Prevent connection flooding
3. **DDoS Protection**: Use Cloudflare or similar
4. **Network Isolation**: Private networks for backend services
5. **Secret Management**: Use proper secret management systems

## Cost Optimization

1. **Right-sizing**: Monitor resource usage and adjust
2. **Reserved Instances**: Use cloud provider reservations
3. **Spot Instances**: For non-critical workloads
4. **CDN Caching**: Reduce bandwidth costs

---

*"In silence, we scale."* - The Collective
