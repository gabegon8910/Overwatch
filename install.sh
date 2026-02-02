#!/usr/bin/env bash
#
# Overwatch Installer
# https://github.com/gabegon8910/overwatch
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/gabegon8910/overwatch/main/install.sh | bash
#
# With options:
#   curl -fsSL ... | bash -s -- --dir /opt/overwatch --version 2.2.3
#

if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

INSTALL_DIR="${INSTALL_DIR:-$HOME/overwatch}"
OW_VERSION="${OW_VERSION:-latest}"
REPO_URL="https://raw.githubusercontent.com/gabegon8910/overwatch/main"

while [[ $# -gt 0 ]]; do
    case $1 in
        --dir)      INSTALL_DIR="$2"; shift 2 ;;
        --version)  OW_VERSION="$2"; shift 2 ;;
        --help)
            echo "Overwatch Installer"
            echo ""
            echo "Usage: install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dir DIR          Installation directory (default: ~/overwatch)"
            echo "  --version VERSION  Image version to install (default: latest)"
            echo "  --help             Show this help message"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "   ____                             _       _     "
    echo "  / __ \\                           | |     | |    "
    echo " | |  | |_   _____ _ ____      __ _| |_ ___| |__  "
    echo " | |  | \\ \\ / / _ \\ '__\\ \\ /\\ / / _\` | __/ __| '_ \\ "
    echo " | |__| |\\ V /  __/ |   \\ V  V / (_| | || (__| | | |"
    echo "  \\____/  \\_/ \\___|_|    \\_/\\_/ \\__,_|\\__\\___|_| |_|"
    echo -e "${NC}"
    echo -e " ${BLUE}Server Management Platform${NC}"
    echo ""
}

check_requirements() {
    log_info "Checking requirements..."
    local missing=()

    if ! command -v docker &>/dev/null; then
        missing+=("docker")
    else
        log_success "Docker found: $(docker --version 2>&1 | head -1)"
    fi

    if ! docker compose version &>/dev/null 2>&1; then
        missing+=("docker-compose-plugin")
    else
        log_success "Docker Compose found: $(docker compose version --short 2>&1)"
    fi

    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        missing+=("curl or wget")
    fi

    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        echo ""
        echo "To install Docker (includes Compose plugin):"
        echo "  curl -fsSL https://get.docker.com | sh"
        echo ""
        exit 1
    fi

    if ! docker info &>/dev/null; then
        log_error "Docker daemon is not running."
        echo "  sudo systemctl start docker"
        exit 1
    fi

    log_success "All requirements met"
    echo ""
}

download_files() {
    log_info "Setting up ${INSTALL_DIR}..."
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    log_info "Downloading docker-compose.yml..."
    curl -fsSL "${REPO_URL}/docker-compose.yml" -o docker-compose.yml

    if [ ! -f .env ]; then
        curl -fsSL "${REPO_URL}/.env.example" -o .env.example
        log_success "Files downloaded"
    else
        log_warn ".env already exists, keeping current configuration"
        log_success "docker-compose.yml updated"
    fi
    echo ""
}

setup_environment() {
    cd "$INSTALL_DIR"

    if [ -f .env ]; then
        return
    fi

    log_info "Generating environment configuration..."

    SECRET_KEY=$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 64)
    ENCRYPTION_KEY=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
    POSTGRES_PASSWORD=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)

    local detected_ip
    detected_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
    local default_url="http://${detected_ip}"

    echo ""
    echo -e "${CYAN}What is the public URL for this Overwatch instance?${NC}"
    echo "This is used for OAuth callbacks, email links, and API references."
    echo "Examples: https://overwatch.example.com, http://192.168.1.100"
    echo ""
    read -p "Public URL [${default_url}]: " USER_URL </dev/tty
    FRONTEND_URL="${USER_URL:-$default_url}"
    echo ""

    cat > .env << EOF
# Overwatch Environment Configuration
# Generated on $(date)

# Docker images
GITHUB_OWNER=gabegon8910
VERSION=${OW_VERSION}

# Database
POSTGRES_USER=ssm_user
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=ssm_db

# Security
SECRET_KEY=${SECRET_KEY}
ENCRYPTION_KEY=${ENCRYPTION_KEY}

# Network
FRONTEND_URL=${FRONTEND_URL}
HTTP_PORT=80

# Licensing
LICENSE_SERVER_URL=https://ow-license1.byteforce.us/v1
LICENSE_KEY=
EOF

    log_success "Environment configured with secure random secrets"
    echo ""
}

start_services() {
    cd "$INSTALL_DIR"
    log_info "Pulling Docker images..."
    docker compose pull

    log_info "Starting containers..."
    docker compose up -d

    log_success "Services started"
    echo ""
}

wait_for_ready() {
    log_info "Waiting for Overwatch to be ready..."
    local attempts=0
    local max=60

    while [ $attempts -lt $max ]; do
        if curl -s http://localhost:8000/api/v1/setup/status >/dev/null 2>&1; then
            log_success "Overwatch is ready"
            return
        fi
        attempts=$((attempts + 1))
        echo -n "."
        sleep 2
    done
    echo ""
    log_warn "Backend is still starting. Check logs: docker compose logs -f backend"
}

print_success() {
    local ip_address
    ip_address=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
    local port
    port=$(grep -oP 'HTTP_PORT=\K.*' "$INSTALL_DIR/.env" 2>/dev/null || echo "80")

    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}   Overwatch installed successfully!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    if [ "$port" = "80" ]; then
        echo -e "  Open: ${CYAN}http://${ip_address}${NC}"
    else
        echo -e "  Open: ${CYAN}http://${ip_address}:${port}${NC}"
    fi
    echo ""
    echo "  1. Open the URL above in your browser"
    echo "  2. Create your admin account in the setup wizard"
    echo "  3. Start adding servers"
    echo ""
    echo "Useful commands:"
    echo "  cd ${INSTALL_DIR}"
    echo "  docker compose ps              # Status"
    echo "  docker compose logs -f         # Logs"
    echo "  docker compose down            # Stop"
    echo "  docker compose pull && docker compose up -d   # Upgrade"
    echo ""
    echo "Documentation: https://github.com/gabegon8910/overwatch"
    echo ""
}

main() {
    print_banner
    echo "This will install Overwatch to: ${INSTALL_DIR}"
    echo ""
    check_requirements
    download_files
    setup_environment
    start_services
    wait_for_ready
    print_success
}

main "$@"
