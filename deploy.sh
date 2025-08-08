#!/bin/bash

# The Collective Deployment Script
# This script provides easy commands for managing The Collective

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Docker and Docker Compose are installed
check_dependencies() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose is not installed or not in PATH"
        exit 1
    fi

    print_success "Docker and Docker Compose are available"
}

# Development commands
dev_start() {
    print_status "Starting development environment..."
    docker-compose -f docker-compose.dev.yml up -d
    print_success "Development Redis is running"
    print_status "You can now run 'mix phx.server' to start The Collective"
    print_status "Redis Commander available at: http://localhost:8081"
}

dev_stop() {
    print_status "Stopping development environment..."
    docker-compose -f docker-compose.dev.yml down
    print_success "Development environment stopped"
}

dev_logs() {
    docker-compose -f docker-compose.dev.yml logs -f
}

# Production commands
prod_build() {
    print_status "Building production images..."
    docker-compose build --no-cache
    print_success "Production images built successfully"
}

prod_start() {
    print_status "Starting production environment..."
    docker-compose up -d
    print_success "The Collective is awakening..."
    print_status "Application available at: http://localhost:4000"
    print_status "Redis Commander available at: http://localhost:8081 (with --profile dev)"
}

prod_stop() {
    print_status "Stopping production environment..."
    docker-compose down
    print_success "The Collective has entered dormancy"
}

prod_restart() {
    prod_stop
    prod_start
}

prod_logs() {
    docker-compose logs -f app
}

prod_shell() {
    print_status "Connecting to The Collective application container..."
    docker-compose exec app ./bin/the_collective remote
}

# Utility commands
generate_secret() {
    print_status "Generating new secret key base..."
    if command -v mix &> /dev/null; then
        SECRET=$(mix phx.gen.secret)
        echo "SECRET_KEY_BASE=$SECRET"
        print_success "Secret generated. Add this to your .env file or Docker environment"
    else
        print_error "Elixir/Mix not found. Install Elixir or use: openssl rand -base64 64"
    fi
}

redis_cli() {
    print_status "Connecting to Redis CLI..."
    docker-compose exec redis redis-cli
}

status() {
    print_status "The Collective Status:"
    docker-compose ps
}

cleanup() {
    print_warning "This will remove all containers, volumes, and images for The Collective"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Cleaning up..."
        docker-compose down -v --rmi all
        docker-compose -f docker-compose.dev.yml down -v --rmi all
        print_success "Cleanup complete"
    else
        print_status "Cleanup cancelled"
    fi
}

# Help
show_help() {
    echo "The Collective - Deployment Management Script"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Development Commands:"
    echo "  dev:start     Start development Redis environment"
    echo "  dev:stop      Stop development environment"
    echo "  dev:logs      View development logs"
    echo ""
    echo "Production Commands:"
    echo "  prod:build    Build production Docker images"
    echo "  prod:start    Start production environment"
    echo "  prod:stop     Stop production environment"
    echo "  prod:restart  Restart production environment"
    echo "  prod:logs     View production application logs"
    echo "  prod:shell    Connect to application shell"
    echo ""
    echo "Utility Commands:"
    echo "  secret        Generate a new secret key base"
    echo "  redis         Connect to Redis CLI"
    echo "  status        Show container status"
    echo "  cleanup       Remove all containers and data (DESTRUCTIVE)"
    echo "  help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 dev:start      # Start development environment"
    echo "  $0 prod:build     # Build and start production"
    echo "  $0 prod:start"
    echo "  $0 redis          # Access Redis CLI"
}

# Main script logic
main() {
    check_dependencies

    case "${1:-help}" in
        "dev:start")
            dev_start
            ;;
        "dev:stop")
            dev_stop
            ;;
        "dev:logs")
            dev_logs
            ;;
        "prod:build")
            prod_build
            ;;
        "prod:start")
            prod_start
            ;;
        "prod:stop")
            prod_stop
            ;;
        "prod:restart")
            prod_restart
            ;;
        "prod:logs")
            prod_logs
            ;;
        "prod:shell")
            prod_shell
            ;;
        "secret")
            generate_secret
            ;;
        "redis")
            redis_cli
            ;;
        "status")
            status
            ;;
        "cleanup")
            cleanup
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

main "$@"
