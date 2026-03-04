#!/bin/bash

#######################################################################
# ERPNext v16 Development Setup Script
# 
# This script sets up a complete Frappe v16 development environment
# with Docker, fixing common issues with Python and Node version mismatches.
#
# Usage:
#   ./setup_v16.sh [options]
#
# Options:
#   -b, --bench-name      Bench directory name (default: frappe-bench)
#   -s, --site-name       Site name (default: development16.localhost)
#   -a, --admin-password  Admin password (default: admin)
#   -r, --db-root-password MariaDB root password (default: 123 or $DB_ROOT_PASSWORD)
#   -p, --python-version  Python version (default: 3.14)
#   -n, --node-version    Node version (default: 24)
#   --skip-bench-init     Skip bench initialization (if already exists)
#   --skip-docker-up      Skip starting Docker services
#   --docker-compose-file Compose file path to start services
#   --docker-project-dir  Compose project directory (default: current dir)
#   --docker-project-name Compose project name/container prefix
#                         (also used for VS Code DevContainer setup)
#   --docker-app-port     Host port to expose Docker frontend service
#                         (starts compose 'frontend'; default from compose)
#   --clone-dir           Directory to clone frappe_docker to (default: frappe_docker)
#                         (used automatically if compose file is missing)
#   --install-webshop     Install webshop app
#   --install-hrms        Install HRMS app
#   --install-crm         Install CRM app
#   --install-deps        Install pyenv and nvm if not present
#   --bare-metal          Use localhost instead of Docker service names
#   --init-vscode         Initialize VS Code devcontainer setup
#                         (clones frappe_docker, sets up .devcontainer)
#   --skip-clone          Skip cloning if directory already exists
#   -h, --help            Show this help message
#
# Prerequisites:
#   - Docker running (or MariaDB/Redis for bare-metal)
#   - pyenv installed (or use --install-deps)
#   - nvm installed (or use --install-deps)
#   - At least 8GB RAM
#
#######################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Default values
BENCH_NAME="frappe-bench"
SITE_NAME="development16.localhost"
ADMIN_PASSWORD="admin"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-123}"
PYTHON_VERSION="3.14"
NODE_VERSION="24"
FRAPPE_BRANCH="version-16"
SKIP_BENCH_INIT=false
SKIP_DOCKER_UP=false
DOCKER_COMPOSE_FILE=""
DOCKER_PROJECT_DIR="$(pwd)"
DOCKER_PROJECT_NAME=""
FRONTEND_PORT="${FRONTEND_PORT:-}"
SOCKETIO_HOST_PORT="${SOCKETIO_HOST_PORT:-}"
INSTALL_WEBSHOP=false
INSTALL_HRMS=false
INSTALL_CRM=false
INSTALL_DEPS=false
BARE_METAL=false
INIT_VSCODE=false
CLONE_DIR="frappe_docker"
SKIP_CLONE=false

# Save original directory (for VS Code init)
ORIGINAL_DIR="$(pwd)"
CLONE_DIR_ABS=""

# Database/Redis hosts (will be set based on --bare-metal)
DB_HOST="mariadb"
REDIS_CACHE="redis://redis-cache:6379"
REDIS_QUEUE="redis://redis-queue:6379"
DB_SERVICE="mariadb"
REDIS_CACHE_SERVICE="redis-cache"
REDIS_QUEUE_SERVICE="redis-queue"
REDIS_SOCKETIO_SERVICE="redis-socketio"

COMPOSE_CMD=""
COMPOSE_FILE_RESOLVED=""
COMPOSE_PROJECT_DIR_RESOLVED=""

# Helper functions
print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_success() {
    echo -e "${GREEN}[✓] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[!] $1${NC}"
}

print_error() {
    echo -e "${RED}[✗] $1${NC}"
}

print_info() {
    echo -e "${BLUE}[i] $1${NC}"
}

print_step() {
    echo -e "${CYAN}==>$1${NC}"
}

print_vscode() {
    echo -e "${MAGENTA}[VS Code]$1${NC}"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
}

show_help() {
    cat << 'EOF'
ERPNext v16 Development Setup Script

Usage: ./setup_v16.sh [options]

Options:
  -b, --bench-name      Bench directory name (default: frappe-bench)
  -s, --site-name       Site name (default: development16.localhost)
  -a, --admin-password  Admin password (default: admin)
  -r, --db-root-password MariaDB root password (default: 123 or $DB_ROOT_PASSWORD)
  -p, --python-version  Python version (default: 3.14)
  -n, --node-version    Node version (default: 24)
  --skip-bench-init     Skip bench initialization (if already exists)
  --skip-docker-up      Skip starting Docker services
  --docker-compose-file Compose file path to start services
  --docker-project-dir  Compose project directory (default: current dir)
  --docker-project-name Compose project name/container prefix
                        (also used for VS Code DevContainer setup)
  --docker-app-port     Host port to expose Docker frontend service
                        (starts compose 'frontend'; default from compose)
  --clone-dir           Directory to clone frappe_docker to (default: frappe_docker)
                        (used automatically if compose file is missing)
  --install-webshop     Install webshop app
  --install-hrms        Install HRMS app
  --install-crm         Install CRM app
  --install-deps        Install pyenv and nvm if not present
  --bare-metal          Use localhost instead of Docker service names
                        (requires MariaDB and Redis running locally)
  --init-vscode         Initialize VS Code devcontainer setup
                        (clones frappe_docker, sets up .devcontainer)
  --skip-clone          Skip cloning if directory already exists
  -h, --help            Show this help message

Examples:
  # Basic setup in devcontainer
  ./setup_v16.sh

  # Initialize VS Code devcontainer from scratch
  ./setup_v16.sh --init-vscode

  # Full setup: clone, init vscode, install all deps
  ./setup_v16.sh --init-vscode --install-deps --install-webshop

  # Use a specific compose file to start MariaDB/Redis
  ./setup_v16.sh --docker-compose-file ../pwd.yml --docker-project-dir ..

  # Also start Docker frontend on host port 8090
  ./setup_v16.sh --docker-compose-file ../pwd.yml --docker-project-dir .. --docker-app-port 8090

  # One-command bootstrap (auto-clones frappe_docker if compose is missing)
  ./setup_v16.sh --clone-dir frappe_docker

  # Install with additional apps
  ./setup_v16.sh --install-webshop --install-hrms

  # Bare-metal setup (no Docker containers for DB/Redis)
  ./setup_v16.sh --bare-metal

Prerequisites:
  - Docker running (or MariaDB/Redis for --bare-metal)
  - pyenv installed (or use --install-deps)
  - nvm installed (or use --install-deps)
  - At least 8GB RAM

VS Code Setup (--init-vscode):
  1. Clones frappe_docker repository
  2. Copies devcontainer-example to .devcontainer
  3. Copies vscode-example to development/.vscode
  4. Installs VS Code Dev Containers extension
  5. Prints instructions to open in VS Code

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--bench-name)
            BENCH_NAME="$2"
            shift 2
            ;;
        -s|--site-name)
            SITE_NAME="$2"
            shift 2
            ;;
        -a|--admin-password)
            ADMIN_PASSWORD="$2"
            shift 2
            ;;
        -r|--db-root-password)
            DB_ROOT_PASSWORD="$2"
            shift 2
            ;;
        -p|--python-version)
            PYTHON_VERSION="$2"
            shift 2
            ;;
        -n|--node-version)
            NODE_VERSION="$2"
            shift 2
            ;;
        --skip-bench-init)
            SKIP_BENCH_INIT=true
            shift
            ;;
        --skip-docker-up)
            SKIP_DOCKER_UP=true
            shift
            ;;
        --docker-compose-file)
            DOCKER_COMPOSE_FILE="$2"
            shift 2
            ;;
        --docker-project-dir)
            DOCKER_PROJECT_DIR="$2"
            shift 2
            ;;
        --docker-project-name)
            DOCKER_PROJECT_NAME="$2"
            shift 2
            ;;
        --docker-app-port)
            FRONTEND_PORT="$2"
            if ! [[ "$FRONTEND_PORT" =~ ^[0-9]+$ ]] || [ "$FRONTEND_PORT" -lt 1 ] || [ "$FRONTEND_PORT" -gt 65535 ]; then
                print_error "Invalid --docker-app-port: $FRONTEND_PORT (expected 1-65535)"
                exit 1
            fi
            shift 2
            ;;
        --install-webshop)
            INSTALL_WEBSHOP=true
            shift
            ;;
        --install-hrms)
            INSTALL_HRMS=true
            shift
            ;;
        --install-crm)
            INSTALL_CRM=true
            shift
            ;;
        --install-deps)
            INSTALL_DEPS=true
            shift
            ;;
        --bare-metal)
            BARE_METAL=true
            shift
            ;;
        --init-vscode)
            INIT_VSCODE=true
            shift
            ;;
        --clone-dir)
            CLONE_DIR="$2"
            shift 2
            ;;
        --skip-clone)
            SKIP_CLONE=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            ;;
    esac
done

delegate_to_no_docker_setup() {
    local script_dir
    local no_docker_script
    local cmd

    script_dir="$(cd "$(dirname "$0")" && pwd)"
    no_docker_script="$script_dir/setup_v16_no_docker.sh"

    if [ ! -f "$no_docker_script" ]; then
        print_error "Bare-metal delegate script not found: $no_docker_script"
        print_info "Create setup_v16_no_docker.sh or run without --bare-metal"
        exit 1
    fi

    if [ ! -x "$no_docker_script" ]; then
        chmod +x "$no_docker_script"
    fi

    cmd=(
        "$no_docker_script"
        --bench-name "$BENCH_NAME"
        --site-name "$SITE_NAME"
        --admin-password "$ADMIN_PASSWORD"
        --db-root-password "$DB_ROOT_PASSWORD"
        --python-version "$PYTHON_VERSION"
        --node-version "$NODE_VERSION"
    )

    if [ "$SKIP_BENCH_INIT" = true ]; then
        cmd+=(--skip-bench-init)
    fi
    if [ "$INSTALL_WEBSHOP" = true ]; then
        cmd+=(--install-webshop)
    fi
    if [ "$INSTALL_HRMS" = true ]; then
        cmd+=(--install-hrms)
    fi
    if [ "$INSTALL_CRM" = true ]; then
        cmd+=(--install-crm)
    fi
    if [ "$INSTALL_DEPS" = true ]; then
        cmd+=(--install-deps)
    fi

    print_info "Delegating --bare-metal setup to $no_docker_script"
    exec "${cmd[@]}"
}

#######################################################################
# DevContainer Detection
#######################################################################
detect_devcontainer() {
    # Check for common devcontainer indicators
    if [ -f /.dockerenv ] || [ -d /workspace/.devcontainer ] || [ -n "$REMOTE_CONTAINERS_IPC" ]; then
        return 0
    fi
    return 1
}

detect_compose_command() {
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
        return 0
    fi

    if check_command docker-compose; then
        COMPOSE_CMD="docker-compose"
        return 0
    fi

    return 1
}

resolve_compose_file() {
    local base_dir
    local candidate
    local candidates

    base_dir="$DOCKER_PROJECT_DIR"

    if [ -n "$DOCKER_COMPOSE_FILE" ]; then
        if [ -f "$DOCKER_COMPOSE_FILE" ]; then
            COMPOSE_FILE_RESOLVED="$DOCKER_COMPOSE_FILE"
        elif [ -f "$base_dir/$DOCKER_COMPOSE_FILE" ]; then
            COMPOSE_FILE_RESOLVED="$base_dir/$DOCKER_COMPOSE_FILE"
        else
            print_error "Compose file not found: $DOCKER_COMPOSE_FILE"
            return 1
        fi

        COMPOSE_PROJECT_DIR_RESOLVED="$(cd "$(dirname "$COMPOSE_FILE_RESOLVED")" && pwd)"
        return 0
    fi

    candidates="pwd.yml docker-compose.yml docker-compose.yaml compose.yml compose.yaml ../pwd.yml ../docker-compose.yml ../docker-compose.yaml"

    for candidate in $candidates; do
        if [ -f "$base_dir/$candidate" ]; then
            COMPOSE_FILE_RESOLVED="$base_dir/$candidate"
            COMPOSE_PROJECT_DIR_RESOLVED="$(cd "$(dirname "$COMPOSE_FILE_RESOLVED")" && pwd)"
            return 0
        fi
    done

    return 1
}

compose_has_service() {
    local service_name="$1"
    grep -qE "^[[:space:]]{2}${service_name}:" "$COMPOSE_FILE_RESOLVED"
}

configure_hosts_from_compose() {
    DB_SERVICE="mariadb"
    REDIS_CACHE_SERVICE="redis-cache"
    REDIS_QUEUE_SERVICE="redis-queue"
    REDIS_SOCKETIO_SERVICE="redis-socketio"

    if compose_has_service "mariadb"; then
        DB_SERVICE="mariadb"
    elif compose_has_service "db"; then
        DB_SERVICE="db"
    fi

    if compose_has_service "redis-cache"; then
        REDIS_CACHE_SERVICE="redis-cache"
    elif compose_has_service "redis_cache"; then
        REDIS_CACHE_SERVICE="redis_cache"
    elif compose_has_service "redis"; then
        REDIS_CACHE_SERVICE="redis"
    fi

    if compose_has_service "redis-queue"; then
        REDIS_QUEUE_SERVICE="redis-queue"
    elif compose_has_service "redis_queue"; then
        REDIS_QUEUE_SERVICE="redis_queue"
    elif compose_has_service "redis"; then
        REDIS_QUEUE_SERVICE="redis"
    fi

    if compose_has_service "redis-socketio"; then
        REDIS_SOCKETIO_SERVICE="redis-socketio"
    elif compose_has_service "redis_socketio"; then
        REDIS_SOCKETIO_SERVICE="redis_socketio"
    else
        REDIS_SOCKETIO_SERVICE="$REDIS_QUEUE_SERVICE"
    fi

    DB_HOST="$DB_SERVICE"
    REDIS_CACHE="redis://$REDIS_CACHE_SERVICE:6379"
    REDIS_QUEUE="redis://$REDIS_QUEUE_SERVICE:6379"

    print_info "Using compose services: db=$DB_SERVICE, redis_cache=$REDIS_CACHE_SERVICE, redis_queue=$REDIS_QUEUE_SERVICE"
}

bootstrap_compose_from_frappe_docker() {
    local auto_clone_dir

    if [ -n "$DOCKER_COMPOSE_FILE" ]; then
        return 1
    fi

    auto_clone_dir="$ORIGINAL_DIR/$CLONE_DIR"

    print_warning "No compose file found near '$DOCKER_PROJECT_DIR'."

    if [ -d "$auto_clone_dir" ]; then
        print_info "Using existing frappe_docker at $auto_clone_dir"
    else
        print_step "Cloning frappe_docker to '$CLONE_DIR' for Docker bootstrap..."
        git clone https://github.com/frappe/frappe_docker "$auto_clone_dir"
        print_success "frappe_docker cloned"
    fi

    DOCKER_PROJECT_DIR="$auto_clone_dir"

    if resolve_compose_file; then
        print_success "Compose file discovered: $COMPOSE_FILE_RESOLVED"
        return 0
    fi

    print_error "Could not find a compose file in '$auto_clone_dir'."
    print_info "Set --docker-compose-file explicitly if your layout is custom"
    return 1
}

sync_script_into_development() {
    local target_dir
    local target_file

    if [ -z "$CLONE_DIR" ]; then
        return 0
    fi

    target_dir="$ORIGINAL_DIR/$CLONE_DIR/development"
    target_file="$target_dir/setup_v16.sh"

    if [ ! -d "$target_dir" ]; then
        return 0
    fi

    cp "$0" "$target_file"
    chmod +x "$target_file"
    print_info "Synced setup script to $target_file"
}

wait_for_tcp() {
    local host="$1"
    local port="$2"
    local label="$3"
    local timeout_seconds=60
    local i

    print_info "Waiting for $label at $host:$port..."
    for ((i=1; i<=timeout_seconds; i++)); do
        if check_command nc; then
            if nc -z "$host" "$port" &> /dev/null; then
                print_success "$label is reachable"
                return 0
            fi
        else
            if (echo > "/dev/tcp/$host/$port") &> /dev/null; then
                print_success "$label is reachable"
                return 0
            fi
        fi
        sleep 1
    done

    print_error "Timeout waiting for $label ($host:$port)"
    return 1
}

start_docker_services() {
    if [ "$BARE_METAL" = true ] || [ "$SKIP_DOCKER_UP" = true ]; then
        return 0
    fi

    if ! detect_compose_command; then
        print_warning "Docker Compose command not found. Skipping service startup."
        print_info "Install Docker Compose or use --skip-docker-up"
        return 0
    fi

    if ! resolve_compose_file; then
        bootstrap_compose_from_frappe_docker
    fi

    sync_script_into_development

    configure_hosts_from_compose

    if ! detect_devcontainer && [ "$DB_HOST" != "localhost" ]; then
        print_error "Compose services use internal hostnames (db/redis-*) that are reachable only inside the DevContainer network."
        print_info "Open '$CLONE_DIR' in VS Code Dev Container and rerun this script there."
        print_info "Alternative: run with --bare-metal against local MariaDB/Redis."
        return 1
    fi

    print_step "Starting MariaDB and Redis services using $COMPOSE_FILE_RESOLVED..."
    local compose_project_args=()
    if [ -n "$DOCKER_PROJECT_NAME" ]; then
        compose_project_args=(-p "$DOCKER_PROJECT_NAME")
        print_info "Using Docker Compose project name: $DOCKER_PROJECT_NAME"
    fi

    local services="$DB_SERVICE $REDIS_CACHE_SERVICE"
    local frontend_started=false
    local frontend_override_file=""
    local compose_file_args=()
    if [ "$REDIS_QUEUE_SERVICE" != "$REDIS_CACHE_SERVICE" ]; then
        services="$services $REDIS_QUEUE_SERVICE"
    fi
    if [ "$REDIS_SOCKETIO_SERVICE" != "$REDIS_QUEUE_SERVICE" ] && [ "$REDIS_SOCKETIO_SERVICE" != "$REDIS_CACHE_SERVICE" ]; then
        services="$services $REDIS_SOCKETIO_SERVICE"
    fi
    if [ -n "$FRONTEND_PORT" ] && compose_has_service "frontend"; then
        services="$services frontend"
        frontend_started=true
        print_info "Docker frontend will be exposed on host port $FRONTEND_PORT"
        frontend_override_file="$(mktemp)"
        cat > "$frontend_override_file" << EOF
services:
  frontend:
    ports:
      - "${FRONTEND_PORT}:8080"
EOF
    elif [ -n "$FRONTEND_PORT" ]; then
        print_warning "--docker-app-port provided, but compose service 'frontend' was not found"
    fi

    compose_file_args=(-f "$COMPOSE_FILE_RESOLVED")
    if [ -n "$frontend_override_file" ]; then
        compose_file_args+=( -f "$frontend_override_file" )
    fi

    if [ "$COMPOSE_CMD" = "docker compose" ]; then
        docker compose "${compose_file_args[@]}" "${compose_project_args[@]}" up -d $services
    else
        docker-compose "${compose_file_args[@]}" "${compose_project_args[@]}" up -d $services
    fi

    if [ -n "$frontend_override_file" ]; then
        rm -f "$frontend_override_file"
    fi

    print_success "Docker services started"
    if [ "$frontend_started" = true ]; then
        print_info "Frontend URL: http://localhost:$FRONTEND_PORT"
    fi

    wait_for_tcp "$DB_HOST" "3306" "MariaDB"

    if [ "$DB_HOST" = "localhost" ]; then
        wait_for_tcp "localhost" "6379" "Redis"
    else
        wait_for_tcp "$REDIS_CACHE_SERVICE" "6379" "Redis cache"
        if [ "$REDIS_QUEUE_SERVICE" != "$REDIS_CACHE_SERVICE" ]; then
            wait_for_tcp "$REDIS_QUEUE_SERVICE" "6379" "Redis queue"
        fi
    fi
}

show_devcontainer_warning() {
    echo ""
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  WARNING: Not running in a DevContainer!                       ║${NC}"
    echo -e "${YELLOW}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║                                                                ║${NC}"
    echo -e "${YELLOW}║  This script is designed for the frappe_docker DevContainer.  ║${NC}"
    echo -e "${YELLOW}║                                                                ║${NC}"
    echo -e "${YELLOW}║  If running outside DevContainer, you need:                    ║${NC}"
    echo -e "${YELLOW}║    - MariaDB running on localhost:3306                         ║${NC}"
    echo -e "${YELLOW}║    - Redis running on localhost:6379                           ║${NC}"
    echo -e "${YELLOW}║                                                                ║${NC}"
    echo -e "${YELLOW}║  Options:                                                      ║${NC}"
    echo -e "${YELLOW}║    1. Use --init-vscode to set up VS Code devcontainer         ║${NC}"
    echo -e "${YELLOW}║    2. Use --bare-metal for local setup without Docker          ║${NC}"
    echo -e "${YELLOW}║                                                                ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

#######################################################################
# VS Code Initialization Functions
#######################################################################

clone_frappe_docker() {
    print_header "Cloning frappe_docker Repository"
    
    # Set absolute path for clone directory
    CLONE_DIR_ABS="$ORIGINAL_DIR/$CLONE_DIR"
    
    if [ -d "$CLONE_DIR_ABS" ] && [ "$SKIP_CLONE" = false ]; then
        print_warning "Directory '$CLONE_DIR' already exists."
        print_info "Use --skip-clone to continue with existing directory"
        read -p "Remove and re-clone? [y/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$CLONE_DIR_ABS"
        else
            print_info "Using existing directory"
            return 0
        fi
    fi
    
    if [ ! -d "$CLONE_DIR_ABS" ]; then
        print_step "Cloning frappe_docker to $CLONE_DIR..."
        cd "$ORIGINAL_DIR"
        git clone https://github.com/frappe/frappe_docker "$CLONE_DIR"
        print_success "Repository cloned"
    else
        print_info "Using existing directory: $CLONE_DIR"
    fi
}

setup_devcontainer() {
    print_header "Setting Up DevContainer Configuration"
    
    if [ ! -d "$CLONE_DIR_ABS" ]; then
        print_error "Directory '$CLONE_DIR_ABS' not found. Clone may have failed."
        return 1
    fi
    
    cd "$CLONE_DIR_ABS"
    
    # Copy devcontainer-example to .devcontainer
    if [ -d "devcontainer-example" ]; then
        if [ -d ".devcontainer" ]; then
            print_warning ".devcontainer already exists"
        else
            print_step "Copying devcontainer-example to .devcontainer..."
            cp -R devcontainer-example .devcontainer
            print_success ".devcontainer created"
        fi
    else
        print_error "devcontainer-example not found in $CLONE_DIR_ABS"
        return 1
    fi
}

remove_intellicode_extension() {
    local devcontainer_json="$1"
    local tmp_file

    if [ ! -f "$devcontainer_json" ]; then
        return 0
    fi

    tmp_file="$(mktemp)"
    awk '
        /"visualstudioexptteam\.vscodeintellicode"/ { next }
        { print }
    ' "$devcontainer_json" > "$tmp_file"
    mv "$tmp_file" "$devcontainer_json"
}

fix_python_interpreter_path() {
    local settings_file="$1"
    local tmp_file

    if [ ! -f "$settings_file" ]; then
        return 0
    fi

    tmp_file="$(mktemp)"
    awk '
        {
            gsub("\\$\\{workspaceFolder\\}/frappe-bench/env/bin/python", "/usr/bin/python3")
            print
        }
    ' "$settings_file" > "$tmp_file"
    mv "$tmp_file" "$settings_file"
}

prompt_vscode_runtime_config() {
    local input
    local socketio_default

    if [ ! -t 0 ]; then
        if [ -z "$DOCKER_PROJECT_NAME" ]; then
            DOCKER_PROJECT_NAME="frappe16"
            print_info "No TTY detected, defaulting Docker project name to '$DOCKER_PROJECT_NAME'"
        fi
        if [ -z "$FRONTEND_PORT" ]; then
            FRONTEND_PORT="8000"
            print_info "No TTY detected, defaulting Docker app port to $FRONTEND_PORT"
        fi
        if [ -z "$SOCKETIO_HOST_PORT" ]; then
            SOCKETIO_HOST_PORT="9000"
            print_info "No TTY detected, defaulting Docker Socket.IO port to $SOCKETIO_HOST_PORT"
        fi
        return 0
    fi

    if [ -z "$DOCKER_PROJECT_NAME" ]; then
        read -r -p "Docker project name (container prefix) [frappe16]: " input
        DOCKER_PROJECT_NAME="${input:-frappe16}"
    fi

    if [ -z "$FRONTEND_PORT" ]; then
        while true; do
            read -r -p "Docker app host port [8000]: " input
            FRONTEND_PORT="${input:-8000}"
            if [[ "$FRONTEND_PORT" =~ ^[0-9]+$ ]] && [ "$FRONTEND_PORT" -ge 1 ] && [ "$FRONTEND_PORT" -le 65535 ]; then
                break
            fi
            print_warning "Please enter a valid port between 1 and 65535"
        done
    fi

    socketio_default="${SOCKETIO_HOST_PORT:-9000}"
    while true; do
        read -r -p "Docker Socket.IO host port [$socketio_default]: " input
        SOCKETIO_HOST_PORT="${input:-$socketio_default}"
        if [[ "$SOCKETIO_HOST_PORT" =~ ^[0-9]+$ ]] && [ "$SOCKETIO_HOST_PORT" -ge 1 ] && [ "$SOCKETIO_HOST_PORT" -le 65535 ]; then
            break
        fi
        print_warning "Please enter a valid port between 1 and 65535"
    done
}

upsert_env_var() {
    local file="$1"
    local key="$2"
    local value="$3"
    local tmp_file

    tmp_file="$(mktemp)"
    if [ -f "$file" ]; then
        awk -v key="$key" -v value="$value" '
            BEGIN { replaced=0 }
            $0 ~ "^" key "=" {
                print key "=" value
                replaced=1
                next
            }
            { print }
            END {
                if (!replaced) {
                    print key "=" value
                }
            }
        ' "$file" > "$tmp_file"
    else
        printf '%s=%s\n' "$key" "$value" > "$tmp_file"
    fi

    mv "$tmp_file" "$file"
}

configure_devcontainer_runtime() {
    local devcontainer_dir
    local env_file
    local compose_file
    local tmp_file

    if [ ! -d "$CLONE_DIR_ABS" ]; then
        return 0
    fi

    devcontainer_dir="$CLONE_DIR_ABS/.devcontainer"
    env_file="$devcontainer_dir/.env"
    compose_file="$devcontainer_dir/docker-compose.yml"

    mkdir -p "$devcontainer_dir"
    print_step "Persisting DevContainer Docker settings..."

    if [ -n "$DOCKER_PROJECT_NAME" ]; then
        upsert_env_var "$env_file" "COMPOSE_PROJECT_NAME" "$DOCKER_PROJECT_NAME"
        print_success "DevContainer compose project name set to '$DOCKER_PROJECT_NAME'"
    fi

    if [ -n "$FRONTEND_PORT" ]; then
        upsert_env_var "$env_file" "FRAPPE_HTTP_PORT" "$FRONTEND_PORT"
        upsert_env_var "$env_file" "FRAPPE_SOCKETIO_PORT" "$SOCKETIO_HOST_PORT"
        print_success "DevContainer app host ports set to '$FRONTEND_PORT' (HTTP) and '$SOCKETIO_HOST_PORT' (Socket.IO)"
    fi

    if [ -f "$compose_file" ]; then
        tmp_file="$(mktemp)"
        awk '
            /^[[:space:]]*-[[:space:]]*8000-8005:8000-8005[[:space:]]*$/ {
                print "      - \"${FRAPPE_HTTP_PORT:-8000}:8000\""
                next
            }
            /^[[:space:]]*-[[:space:]]*9000-9005:9000-9005[[:space:]]*$/ {
                print "      - \"${FRAPPE_SOCKETIO_PORT:-9000}:9000\""
                next
            }
            { print }
        ' "$compose_file" > "$tmp_file"
        mv "$tmp_file" "$compose_file"
    else
        print_warning "DevContainer compose file not found at $compose_file"
    fi
}

setup_vscode_config() {
    print_header "Setting Up VS Code Configuration"
    
    if [ ! -d "$CLONE_DIR_ABS" ]; then
        print_error "Directory '$CLONE_DIR_ABS' not found. Clone may have failed."
        return 1
    fi
    
    cd "$CLONE_DIR_ABS"
    
    # Check if development directory exists
    if [ ! -d "development" ]; then
        print_warning "'development' directory not found, creating..."
        mkdir -p development
    fi
    
    # Copy vscode-example to development/.vscode
    if [ -d "development/vscode-example" ]; then
        if [ -d "development/.vscode" ]; then
            print_warning "development/.vscode already exists"
        else
            print_step "Copying vscode-example to development/.vscode..."
            cp -R development/vscode-example development/.vscode
            print_success "development/.vscode created"
        fi
    else
        print_warning "development/vscode-example not found, skipping..."
    fi

    fix_python_interpreter_path "$CLONE_DIR_ABS/development/vscode-example/settings.json"
    fix_python_interpreter_path "$CLONE_DIR_ABS/development/.vscode/settings.json"
    remove_intellicode_extension "$CLONE_DIR_ABS/devcontainer-example/devcontainer.json"
    remove_intellicode_extension "$CLONE_DIR_ABS/.devcontainer/devcontainer.json"
}

install_vscode_extensions() {
    print_header "Installing VS Code Extensions"
    
    # Check if code command is available
    if ! check_command code; then
        print_warning "'code' command not available. Skipping extension installation."
        print_info "Install manually: code --install-extension ms-vscode-remote.remote-containers"
        return 0
    fi
    
    # Install Dev Containers extension
    print_step "Installing Dev Containers extension..."
    code --install-extension ms-vscode-remote.remote-containers 2>/dev/null || true
    print_success "Extensions installed"
}

show_vscode_instructions() {
    echo ""
    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║  VS Code DevContainer Setup Complete!                          ║${NC}"
    echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}║  Next steps:                                                   ║${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}║  1. Open VS Code:                                               ║${NC}"
    echo -e "${MAGENTA}║     code $CLONE_DIR_ABS"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}║  2. Open Command Palette (Ctrl+Shift+P / Cmd+Shift+P)          ║${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}║  3. Run: Dev Containers: Reopen in Container                   ║${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}║  4. Once inside the container, run this script again:           ║${NC}"
    echo -e "${MAGENTA}║     ./setup_v16.sh [options]                                   ║${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

run_vscode_init() {
    prompt_vscode_runtime_config

    clone_frappe_docker
    sync_script_into_development
    setup_devcontainer
    configure_devcontainer_runtime
    setup_vscode_config
    install_vscode_extensions
    show_vscode_instructions
    
    echo ""
    print_info "VS Code initialization complete. Exiting."
    print_info "Run this script again inside the DevContainer to complete setup."
    exit 0
}

#######################################################################
# Install pyenv
#######################################################################
install_pyenv() {
    print_step "Installing pyenv..."
    
    # Check if already installed
    if [ -d "$HOME/.pyenv" ]; then
        print_warning "pyenv directory exists, skipping..."
    else
        curl -fsSL https://pyenv.run | bash
    fi
    
    # Set up environment for current session
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    
    # Initialize pyenv
    if [ -d "$PYENV_ROOT" ]; then
        eval "$(pyenv init -)"
    fi
    
    # Add to shell config if not present
    local shell_rc="$HOME/.bashrc"
    if [ -n "$ZSH_VERSION" ]; then
        shell_rc="$HOME/.zshrc"
    fi
    
    if ! grep -q 'pyenv init' "$shell_rc" 2>/dev/null; then
        print_info "Adding pyenv to $shell_rc..."
        cat >> "$shell_rc" << 'EOF'

# pyenv configuration
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
EOF
    fi
    
    print_success "pyenv installed"
}

refresh_pyenv_definitions() {
    if [ -d "$PYENV_ROOT/.git" ] && check_command git; then
        print_info "Updating pyenv definitions..."
        git -C "$PYENV_ROOT" pull --ff-only &> /dev/null || true
    fi

    if check_command brew && [[ "$OSTYPE" == darwin* ]]; then
        print_info "Checking Homebrew pyenv updates..."
        brew upgrade pyenv &> /dev/null || true
    fi
}

#######################################################################
# Install nvm
#######################################################################
install_nvm() {
    print_step "Installing nvm..."
    
    # Get latest nvm version
    local NVM_VERSION="v0.40.1"
    
    # Check if already installed
    if [ -d "$HOME/.nvm" ]; then
        print_warning "nvm directory exists, skipping..."
    else
        curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
    fi
    
    # Set up environment for current session
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    # Add to shell config if not present
    local shell_rc="$HOME/.bashrc"
    if [ -n "$ZSH_VERSION" ]; then
        shell_rc="$HOME/.zshrc"
    fi
    
    if ! grep -q 'nvm.sh' "$shell_rc" 2>/dev/null; then
        print_info "Adding nvm to $shell_rc..."
        cat >> "$shell_rc" << 'EOF'

# nvm configuration
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF
    fi
    
    print_success "nvm installed"
}

#######################################################################
# Show pyenv installation instructions
#######################################################################
show_pyenv_install_help() {
    echo ""
    echo -e "${YELLOW}To install pyenv, run:${NC}"
    echo ""
    echo "  curl https://pyenv.run | bash"
    echo ""
    echo -e "${YELLOW}Then add to your shell config (~/.bashrc or ~/.zshrc):${NC}"
    echo ""
    echo '  export PYENV_ROOT="$HOME/.pyenv"'
    echo '  [[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"'
    echo '  eval "$(pyenv init -)"'
    echo ""
    echo -e "${YELLOW}After that, restart your shell or run:${NC}"
    echo "  source ~/.bashrc"
    echo ""
    echo -e "${YELLOW}Or re-run this script with --install-deps to auto-install.${NC}"
    echo ""
}

#######################################################################
# Show nvm installation instructions
#######################################################################
show_nvm_install_help() {
    echo ""
    echo -e "${YELLOW}To install nvm, run:${NC}"
    echo ""
    echo "  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash"
    echo ""
    echo -e "${YELLOW}Then add to your shell config (~/.bashrc or ~/.zshrc):${NC}"
    echo ""
    echo '  export NVM_DIR="$HOME/.nvm"'
    echo '  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
    echo ""
    echo -e "${YELLOW}After that, restart your shell or run:${NC}"
    echo "  source ~/.bashrc"
    echo ""
    echo -e "${YELLOW}Or re-run this script with --install-deps to auto-install.${NC}"
    echo ""
}

#######################################################################
# Main Script
#######################################################################

# If --init-vscode is set, run VS Code initialization and exit
if [ "$INIT_VSCODE" = true ]; then
    run_vscode_init
fi

# If --bare-metal is set, delegate to dedicated non-Docker script
if [ "$BARE_METAL" = true ]; then
    delegate_to_no_docker_setup
fi

# Check if running in DevContainer
if ! detect_devcontainer && [ "$BARE_METAL" = false ]; then
    show_devcontainer_warning
    print_warning "Continuing in Docker mode outside DevContainer"
    print_info "Tip: use --docker-compose-file to point to your compose file"
fi

# Set bare-metal hosts if needed
if [ "$BARE_METAL" = true ]; then
    print_warning "Running in bare-metal mode"
    DB_HOST="localhost"
    REDIS_CACHE="redis://localhost:6379"
    REDIS_QUEUE="redis://localhost:6379"
fi

#######################################################################
# Step 1: Check/Install Prerequisites
#######################################################################
print_header "Step 1: Checking Prerequisites"

# Check Docker (skip for bare-metal)
if [ "$BARE_METAL" = false ]; then
    if detect_devcontainer; then
        print_info "Running inside DevContainer; using existing DB/Redis services"
    else
        if ! docker info &> /dev/null; then
            print_error "Docker is not running. Please start Docker and try again."
            exit 1
        fi
        print_success "Docker is running"
        start_docker_services
    fi
else
    print_warning "Skipping Docker check (bare-metal mode)"
    print_info "Ensure MariaDB and Redis are running on localhost"
fi

# Check/install pyenv
if ! check_command pyenv; then
    if [ "$INSTALL_DEPS" = true ]; then
        install_pyenv
    else
        print_error "pyenv is not installed."
        show_pyenv_install_help
        exit 1
    fi
fi

# Initialize pyenv for current session
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)" 2>/dev/null || true
print_success "pyenv is installed"

# Check/install nvm
if [ ! -d "$HOME/.nvm" ] && [ ! -d "$NVM_DIR" ]; then
    if [ "$INSTALL_DEPS" = true ]; then
        install_nvm
    else
        print_error "nvm is not installed."
        show_nvm_install_help
        exit 1
    fi
fi

# Source nvm
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
print_success "nvm is installed"

#######################################################################
# Step 2: Install and Configure Python
#######################################################################
print_header "Step 2: Installing Python $PYTHON_VERSION"

# Install Python if not already installed
if ! pyenv versions | grep -qE "^\s*${PYTHON_VERSION}(\s|$)"; then
    if ! pyenv install --list | sed 's/^[[:space:]]*//' | grep -qx "$PYTHON_VERSION"; then
        refresh_pyenv_definitions

        if ! pyenv install --list | sed 's/^[[:space:]]*//' | grep -qx "$PYTHON_VERSION"; then
        MAJOR_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f1,2)
        LATEST_MATCH=$(pyenv install --list | sed 's/^[[:space:]]*//' | grep -E "^${MAJOR_MINOR}\.[0-9]+$" | tail -1)

        if [ -n "$LATEST_MATCH" ]; then
            print_warning "Python version '$PYTHON_VERSION' not available in pyenv. Using '$LATEST_MATCH' instead."
            PYTHON_VERSION="$LATEST_MATCH"
        else
            print_error "Python version '$PYTHON_VERSION' not found in pyenv definitions."
            print_info "Try: brew update && brew upgrade pyenv"
            exit 1
        fi
        fi
    fi

    print_info "Installing Python $PYTHON_VERSION (this may take a few minutes)..."
    pyenv install "$PYTHON_VERSION"
fi
print_success "Python $PYTHON_VERSION is installed"

# Set as global
pyenv global "$PYTHON_VERSION"
print_success "Python $PYTHON_VERSION set as global"

# Verify
PYTHON_PATH="$HOME/.pyenv/versions/$PYTHON_VERSION/bin/python3"
if [ ! -f "$PYTHON_PATH" ]; then
    print_error "Python binary not found at $PYTHON_PATH"
    exit 1
fi

print_info "Python version: $($PYTHON_PATH --version)"

#######################################################################
# Step 3: Install and Configure Node.js
#######################################################################
print_header "Step 3: Installing Node.js $NODE_VERSION"

# Install Node if not already installed
if ! nvm ls "$NODE_VERSION" &> /dev/null 2>&1; then
    print_info "Installing Node.js $NODE_VERSION..."
    nvm install "$NODE_VERSION"
fi
print_success "Node.js $NODE_VERSION is installed"

# Set as default
nvm alias default "$NODE_VERSION" 2>/dev/null || true
nvm use "$NODE_VERSION"
print_success "Node.js $NODE_VERSION set as default"

# Verify
NODE_VERSION_OUTPUT=$(node -v)
print_info "Node version: $NODE_VERSION_OUTPUT"

#######################################################################
# Step 4: Install frappe-bench with Correct Python
#######################################################################
print_header "Step 4: Installing frappe-bench with Python $PYTHON_VERSION"

BENCH_BIN="$HOME/.pyenv/versions/$PYTHON_VERSION/bin/bench"

# Always reinstall to ensure correct version
print_info "Installing/upgrading frappe-bench..."
$PYTHON_PATH -m pip install --upgrade frappe-bench --quiet

if [ ! -f "$BENCH_BIN" ]; then
    print_error "Failed to install frappe-bench"
    exit 1
fi
print_success "frappe-bench installed"

BENCH_VERSION=$($BENCH_BIN --version)
print_info "bench version: $BENCH_VERSION"

#######################################################################
# Step 5: Configure PATH
#######################################################################
print_header "Step 5: Configuring PATH"

NODE_BIN_DIR=$(nvm which "$NODE_VERSION" | xargs dirname)

PATH_ENTRY="export PATH=\"$HOME/.pyenv/versions/$PYTHON_VERSION/bin:$NODE_BIN_DIR:\$HOME/.local/bin:\$PATH\""

# Determine shell config file
SHELL_RC="$HOME/.bashrc"
if [ -n "$ZSH_VERSION" ]; then
    SHELL_RC="$HOME/.zshrc"
fi

# Check if already in shell config
if ! grep -q "Frappe v16 Development" "$SHELL_RC" 2>/dev/null; then
    print_info "Adding PATH configuration to $SHELL_RC..."
    echo "" >> "$SHELL_RC"
    echo "# Frappe v16 Development - Use Python $PYTHON_VERSION and Node $NODE_VERSION first" >> "$SHELL_RC"
    echo "$PATH_ENTRY" >> "$SHELL_RC"
    print_success "PATH configuration added to $SHELL_RC"
else
    print_info "PATH configuration already exists in $SHELL_RC"
fi

# Apply for current session
export PATH="$HOME/.pyenv/versions/$PYTHON_VERSION/bin:$NODE_BIN_DIR:$HOME/.local/bin:$PATH"
hash -r

# Verify
WHICH_BENCH=$(which bench 2>/dev/null || echo "not found")
print_info "bench location: $WHICH_BENCH"
print_info "python location: $(which python3 2>/dev/null || echo 'not found')"
print_info "node location: $(which node 2>/dev/null || echo 'not found')"

#######################################################################
# Step 6: Fix Yarn
#######################################################################
print_header "Step 6: Configuring Yarn"

corepack enable 2>/dev/null || true
corepack prepare yarn@1.22.22 --activate 2>/dev/null || true
print_success "Yarn configured"

YARN_VERSION=$(yarn -v 2>/dev/null || echo "not available")
print_info "Yarn version: $YARN_VERSION"

#######################################################################
# Step 7: Initialize Bench
#######################################################################
print_header "Step 7: Initializing Bench"

if [ "$SKIP_BENCH_INIT" = true ]; then
    print_warning "Skipping bench initialization (--skip-bench-init)"
    if [ ! -d "$BENCH_NAME" ]; then
        print_error "Bench '$BENCH_NAME' does not exist. Remove --skip-bench-init or create it first."
        exit 1
    fi
elif [ -d "$BENCH_NAME" ]; then
    print_warning "Bench '$BENCH_NAME' already exists. Skipping initialization."
else
    print_info "Initializing bench with Frappe $FRAPPE_BRANCH..."
    bench init --skip-redis-config-generation --frappe-branch "$FRAPPE_BRANCH" "$BENCH_NAME"
    print_success "Bench initialized"
fi

cd "$BENCH_NAME"

#######################################################################
# Step 8: Configure Database and Redis Hosts
#######################################################################
print_header "Step 8: Configuring Database and Redis Hosts"

bench set-config -g db_host "$DB_HOST"
bench set-config -g redis_cache "$REDIS_CACHE"
bench set-config -g redis_queue "$REDIS_QUEUE"
bench set-config -g redis_socketio "$REDIS_QUEUE"
print_success "Hosts configured (db: $DB_HOST, redis: ${REDIS_CACHE#redis://})"

#######################################################################
# Step 9: Create Site
#######################################################################
print_header "Step 9: Creating Site"

if [ -d "sites/$SITE_NAME" ]; then
    print_warning "Site '$SITE_NAME' already exists. Skipping site creation."
else
    print_info "Creating site '$SITE_NAME'..."
    bench new-site \
        --db-root-password "$DB_ROOT_PASSWORD" \
        --admin-password "$ADMIN_PASSWORD" \
        --mariadb-user-host-login-scope=% \
        "$SITE_NAME"
    print_success "Site created"
fi

#######################################################################
# Step 10: Enable Developer Mode
#######################################################################
print_header "Step 10: Enabling Developer Mode"

bench --site "$SITE_NAME" set-config developer_mode 1
bench --site "$SITE_NAME" clear-cache
print_success "Developer mode enabled"

#######################################################################
# Step 11: Install ERPNext
#######################################################################
print_header "Step 11: Installing ERPNext"

if [ -d "apps/erpnext" ]; then
    print_warning "ERPNext already exists in apps. Skipping get-app."
else
    print_info "Getting ERPNext..."
    bench get-app --branch "$FRAPPE_BRANCH" --resolve-deps erpnext
fi

# Check if installed
if bench --site "$SITE_NAME" list-apps 2>/dev/null | grep -q "erpnext"; then
    print_warning "ERPNext already installed on site. Skipping install-app."
else
    print_info "Installing ERPNext to site..."
    bench --site "$SITE_NAME" install-app erpnext
fi
print_success "ERPNext installed"

#######################################################################
# Step 12: Install Additional Apps
#######################################################################

if [ "$INSTALL_WEBSHOP" = true ]; then
    print_header "Installing Webshop"
    
    if [ -d "apps/webshop" ]; then
        print_warning "Webshop already exists in apps. Skipping get-app."
    else
        print_info "Getting Webshop..."
        bench get-app --branch "$FRAPPE_BRANCH" webshop
    fi
    
    if bench --site "$SITE_NAME" list-apps 2>/dev/null | grep -q "webshop"; then
        print_warning "Webshop already installed on site."
    else
        print_info "Installing Webshop to site..."
        bench --site "$SITE_NAME" install-app webshop
    fi
    print_success "Webshop installed"
fi

if [ "$INSTALL_HRMS" = true ]; then
    print_header "Installing HRMS"
    
    if [ -d "apps/hrms" ]; then
        print_warning "HRMS already exists in apps. Skipping get-app."
    else
        print_info "Getting HRMS..."
        bench get-app --branch "$FRAPPE_BRANCH" hrms
    fi
    
    if bench --site "$SITE_NAME" list-apps 2>/dev/null | grep -q "hrms"; then
        print_warning "HRMS already installed on site."
    else
        print_info "Installing HRMS to site..."
        bench --site "$SITE_NAME" install-app hrms
    fi
    print_success "HRMS installed"
fi

if [ "$INSTALL_CRM" = true ]; then
    print_header "Installing CRM"
    
    if [ -d "apps/crm" ]; then
        print_warning "CRM already exists in apps. Skipping get-app."
    else
        print_info "Getting CRM..."
        bench get-app --branch main crm
    fi
    
    if bench --site "$SITE_NAME" list-apps 2>/dev/null | grep -q "crm"; then
        print_warning "CRM already installed on site."
    else
        print_info "Installing CRM to site..."
        bench --site "$SITE_NAME" install-app crm
    fi
    print_success "CRM installed"
fi

#######################################################################
# Step 13: Final Setup
#######################################################################
print_header "Step 13: Final Setup"

bench use "$SITE_NAME"
print_info "Running migrate..."
bench migrate
print_info "Building assets..."
bench build
print_success "Final setup complete"

#######################################################################
# Done!
#######################################################################
print_header "Setup Complete!"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Your Frappe v16 development environment is ready!            ║${NC}"
echo -e "${GREEN}╠════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║                                                                ║${NC}"
echo -e "${GREEN}║  Site: http://$SITE_NAME:8000"
echo -e "${GREEN}║  Admin Password: $ADMIN_PASSWORD"
echo -e "${GREEN}║                                                                ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "To start the development server:"
echo "  cd $BENCH_NAME && bench start"
echo ""
echo "To open a new terminal with correct environment:"
echo "  source $SHELL_RC"
echo ""
