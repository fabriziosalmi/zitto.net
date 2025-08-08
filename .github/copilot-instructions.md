<!-- Use this file to provide workspace-specific custom instructions to Copilot. For more details, visit https://code.visualstudio.com/docs/copilot/copilot-customization#_use-a-githubcopilotinstructionsmd-file -->

# The Collective - Copilot Instructions

This is "The Collective" - a massively scalable, real-time distributed system for connecting millions of simultaneous users in a shared state of "silence". 

## Project Architecture

- **Language**: Elixir with Phoenix Framework (BEAM VM)
- **State Management**: Redis for atomic, distributed global state
- **Frontend**: Minimal vanilla JavaScript with WebSocket connections
- **Deployment**: Docker Compose for scalability

## Key Concepts

- **Massive Scale**: Designed for 10+ million concurrent WebSocket connections
- **Anonymous & Ephemeral**: No user accounts or individual tracking
- **Global State**: All state stored in Redis with atomic operations
- **Evolution Events**: Milestones trigger broadcasts to all connected users
- **Bell Labs Elegance**: Robust, simple, and performant architecture

## Code Style Guidelines

- Use OTP principles (GenServers, Supervisors)
- Prefer atomic Redis operations (INCR, DECR, SADD)
- Minimize memory usage per connection
- Document for massive scale implications
- Follow Elixir naming conventions
- Keep JavaScript vanilla and lightweight

## Key Files

- `lib/the_collective/chronos.ex` - Time engine (ticks every 5s)
- `lib/the_collective/evolution.ex` - Milestone detection
- `lib/the_collective/redis.ex` - Redis operations
- `lib/the_collective_web/channels/collective_channel.ex` - WebSocket handler
- `priv/static/index.html` - Minimal frontend

## Redis Global State

- `global:concurrent_connections` - Active WebSocket count
- `global:total_connection_seconds` - Accumulated connection time
- `global:unlocked_milestones` - Set of achieved milestones

## When Making Changes

- Consider impact on millions of concurrent connections
- Use atomic Redis operations for consistency
- Test with Docker Compose setup
- Maintain the minimalist, meditative user experience
- Remember: The Collective itself is the player, not individual users
