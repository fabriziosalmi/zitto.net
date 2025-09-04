# Graceful Shutdown and Backpressure Management

This document describes the implementation of graceful shutdown and backpressure management features for The Collective, designed to handle massive scale (10+ million concurrent connections) safely.

## Overview

The implementation adds two key capabilities:

1. **Graceful Shutdown**: Ensures clean termination during deployments/scaling
2. **Backpressure Management**: Prevents system overload during connection surges

## Architecture

### Graceful Shutdown System

The `TheCollective.GracefulShutdown` GenServer coordinates shutdown behavior:

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Deployment    │───▶│  GracefulShutdown │───▶│  Redis Cleanup  │
│   Signal        │    │     Manager       │    │    & Sync       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌──────────────────┐
                       │ Connection Drain │
                       │ (15s timeout)    │
                       └──────────────────┘
```

**Key Features:**
- Connection tracking and registration
- Configurable drain timeouts (15s default)
- Broadcast warnings to connected clients
- Redis state cleanup to prevent inconsistencies
- Integration with OTP supervision tree

### Backpressure Management System

The `TheCollective.BackpressureManager` GenServer implements multiple layers of protection:

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ Incoming        │───▶│ IP Rate Limiting │───▶│ Global Rate     │
│ Connection      │    │ (60/min default) │    │ Limiting        │
└─────────────────┘    └──────────────────┘    │ (1000/s default)│
                                               └─────────────────┘
                                                       │
                                                       ▼
                                               ┌─────────────────┐
                                               │ Capacity Check  │
                                               │ (10M default)   │
                                               └─────────────────┘
```

**Protection Layers:**
1. **Per-IP Rate Limiting**: Prevents individual abuse
2. **Global Rate Limiting**: Controls overall connection velocity  
3. **Capacity Limits**: Enforces maximum concurrent connections
4. **ETS-based Tracking**: Efficient in-memory rate limit storage

## Integration Points

### Application Supervision Tree

Updated to include both managers:

```elixir
children = [
  # ... existing children ...
  {TheCollective.GracefulShutdown, []},
  {TheCollective.BackpressureManager, []},
  # ... rest of children ...
]
```

### WebSocket Connection Flow

1. **Connection Request** → UserSocket
2. **Backpressure Check** → Allow/Deny decision
3. **Graceful Shutdown Check** → Verify system accepting connections
4. **Connection Registration** → Track for shutdown coordination
5. **Normal Operation** → Standard channel handling
6. **Termination** → Unregister and cleanup

### Enhanced Health Checks

New endpoint `/health/status` provides comprehensive system status:

```json
{
  "timestamp": "2024-09-04T20:48:00Z",
  "redis": {
    "status": "ok",
    "concurrent_connections": 1234,
    "total_connection_seconds": 567890,
    "peak_connections": 2000
  },
  "chronos": {
    "tick_count": 1440,
    "active_connections": 1234,
    "uptime_ms": 7200000
  },
  "backpressure": {
    "connections_rejected": 0,
    "rate_limited_ips": 0,
    "global_connections": 1234,
    "config": {
      "connections_per_ip_per_minute": 60,
      "global_connections_per_second": 1000,
      "max_global_connections": 10000000
    }
  },
  "graceful_shutdown": {
    "accepting_connections": true
  }
}
```

## Configuration

### Environment Variables (Production)

```bash
# Backpressure Management
CONNECTIONS_PER_IP_PER_MINUTE=60        # Rate limit per IP
GLOBAL_CONNECTIONS_PER_SECOND=1000      # Global rate limit
MAX_GLOBAL_CONNECTIONS=10000000         # Maximum concurrent connections

# Redis Configuration  
REDIS_URL=redis://redis:6379
```

### Development Configuration

Located in `config/dev.exs`:

```elixir
# More lenient limits for development
config :the_collective, :connections_per_ip_per_minute, 120
config :the_collective, :global_connections_per_second, 2000
config :the_collective, :max_global_connections, 100_000
```

## Operational Behavior

### Normal Operation

- All connections proceed normally
- Rate limiting tracks usage in ETS tables
- Periodic cleanup removes expired entries
- Health checks report system status

### During Connection Surge

1. **IP Rate Limiting**: Blocks excessive connections from single IPs
2. **Global Rate Limiting**: Throttles overall connection velocity
3. **Capacity Limits**: Rejects connections when at maximum capacity
4. **Statistics Tracking**: Records rejection metrics for monitoring

### During Deployment

1. **Shutdown Signal Received**: Manager enters shutdown mode
2. **Stop Accepting New Connections**: UserSocket rejects new connections
3. **Broadcast Warning**: Connected clients receive shutdown notification
4. **Connection Drain**: Wait for connections to naturally terminate
5. **Force Shutdown**: After timeout, force remaining connections closed
6. **Redis Cleanup**: Ensure accurate connection counts in Redis
7. **Process Termination**: Complete application shutdown

## Testing

### Unit Tests

- `test/the_collective_graceful_shutdown_test.exs`: Shutdown behavior tests
- `test/the_collective_backpressure_manager_test.exs`: Rate limiting tests

### Integration Testing

For full system testing, use the Docker Compose setup:

```bash
# Start Redis and application
docker-compose up -d

# Test health endpoints
curl http://localhost:4000/health/status

# Test graceful shutdown
docker-compose stop the_collective

# Observe logs for graceful shutdown sequence
docker-compose logs the_collective
```

## Monitoring

### Key Metrics to Monitor

1. **Connection Statistics**:
   - `concurrent_connections`: Current active connections
   - `peak_connections`: Historical peak
   - `total_connection_seconds`: Cumulative connection time

2. **Backpressure Metrics**:
   - `connections_rejected`: Total rejected connections
   - `rate_limited_ips`: IPs currently rate limited
   - `global_rate_limited`: Global rate limit hits

3. **Shutdown Status**:
   - `accepting_connections`: Whether system accepts new connections

### Alerting Recommendations

- **High Rejection Rate**: May indicate attack or misconfiguration
- **Approaching Capacity**: Scale horizontally before hitting limits
- **Redis Connectivity**: Critical for global state consistency
- **Graceful Shutdown Issues**: Monitor deployment safety

## Performance Considerations

### Memory Usage

- **ETS Tables**: Efficient in-memory storage for rate limiting
- **Per-Connection Overhead**: Minimal additional memory per connection
- **Cleanup Cycles**: Automatic cleanup prevents memory leaks

### Latency Impact

- **Connection Establishment**: Minimal additional latency (~1ms)
- **Rate Limit Checks**: ETS lookups are extremely fast
- **Redis Operations**: Already optimized in existing codebase

### Scalability

- **Horizontal Scaling**: Each node runs independent managers
- **Redis Coordination**: Global state remains consistent across nodes
- **Load Distribution**: Backpressure naturally distributes load

## Security Considerations

- **DDoS Protection**: IP rate limiting provides first line of defense
- **Resource Exhaustion**: Capacity limits prevent resource exhaustion
- **Graceful Degradation**: System remains stable under extreme load
- **State Consistency**: Redis cleanup prevents state corruption

## Future Enhancements

1. **Dynamic Rate Limiting**: Adjust limits based on system load
2. **Geographic Distribution**: Per-region rate limiting
3. **Advanced Analytics**: Connection pattern analysis
4. **Automated Scaling**: Integration with container orchestration
5. **Circuit Breakers**: Enhanced fault tolerance for Redis