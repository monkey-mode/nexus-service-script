#!/bin/bash
# nexus-service.sh - Nexus Network Node Service Manager
# 
# A comprehensive service management script for Nexus Network nodes and logserver.
# Provides installation, configuration, and lifecycle management for systemd services.
#
# Usage:
#   ./nexus-service.sh install [--node-id <id> | --wallet <wallet-address>]
#   ./nexus-service.sh [start|stop|restart|status|logs|remove]
#   ./nexus-service.sh [install-logserver|start-logserver|stop-logserver|logs-logserver|remove-logserver]

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Service Configuration
readonly SERVICE_NAME="nexus-network"
readonly LOGSERVER_NAME="nexus-logserver"
readonly SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
readonly LOGSERVER_FILE="/etc/systemd/system/${LOGSERVER_NAME}.service"

# Default Values
readonly DEFAULT_USER="${USER:-root}"
readonly DEFAULT_WORK_DIR="${HOME:-/root}"
readonly DEFAULT_PORT=80
readonly DEFAULT_NEXUS_BIN="/root/.nexus/bin/nexus-network"

# Logging Configuration
readonly LOG_PREFIX="[NEXUS-SERVICE]"
readonly LOG_LEVEL_INFO="INFO"
readonly LOG_LEVEL_ERROR="ERROR"
readonly LOG_LEVEL_WARN="WARN"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log() {
    local level="$1"
    shift
    echo "${LOG_PREFIX} [${level}] $*" >&2
}

log_info() {
    log "$LOG_LEVEL_INFO" "$@"
}

log_error() {
    log "$LOG_LEVEL_ERROR" "$@"
}

log_warn() {
    log "$LOG_LEVEL_WARN" "$@"
}

check_root() {
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        log_error "This script requires root privileges or sudo access"
        exit 1
    fi
}

validate_wallet_address() {
    local wallet="$1"
    if [[ ! "$wallet" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        log_error "Invalid wallet address format: $wallet"
        log_error "Expected format: 0x followed by 40 hexadecimal characters"
        exit 1
    fi
}

validate_node_id() {
    local node_id="$1"
    if [[ ! "$node_id" =~ ^[0-9]+$ ]]; then
        log_error "Invalid node ID format: $node_id"
        log_error "Node ID must be a numeric value"
        exit 1
    fi
}

check_nexus_binary() {
    if [[ ! -f "$DEFAULT_NEXUS_BIN" ]]; then
        log_error "Nexus binary not found at: $DEFAULT_NEXUS_BIN"
        log_error "Please ensure Nexus CLI is properly installed"
        exit 1
    fi
}

create_systemd_service() {
    local service_file="$1"
    local service_name="$2"
    local exec_start="$3"
    local user="$4"
    local work_dir="$5"
    local description="$6"

    log_info "Creating systemd service file: $service_file"
    
    sudo tee "$service_file" > /dev/null <<EOF
[Unit]
Description=$description
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=$exec_start
Restart=always
RestartSec=5
User=$user
Group=$user
WorkingDirectory=$work_dir
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$service_name

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$work_dir

[Install]
WantedBy=multi-user.target
EOF
}

# =============================================================================
# SERVICE MANAGEMENT FUNCTIONS
# =============================================================================

install_service() {
    local node_id=""
    local wallet_addr=""
    local use_wallet=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --node-id)
                if [[ -z "${2:-}" ]]; then
                    log_error "Missing value for --node-id"
                    exit 1
                fi
                node_id="$2"
                use_wallet=false
                shift 2
                ;;
            --wallet)
                if [[ -z "${2:-}" ]]; then
                    log_error "Missing value for --wallet"
                    exit 1
                fi
                wallet_addr="$2"
                use_wallet=true
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Check that either node-id or wallet is provided
    if [[ -z "$node_id" && -z "$wallet_addr" ]]; then
        log_error "Either --node-id or --wallet must be provided"
        show_usage
        exit 1
    fi

    # Validate inputs
    if [[ "$use_wallet" == true ]]; then
        validate_wallet_address "$wallet_addr"
    else
        validate_node_id "$node_id"
    fi

    check_nexus_binary
    check_root

    log_info "Installing Nexus Network service..."

    # Stop and remove existing service if it exists
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        log_warn "Stopping existing service..."
        sudo systemctl stop "$SERVICE_NAME" || true
    fi

    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        log_warn "Disabling existing service..."
        sudo systemctl disable "$SERVICE_NAME" || true
    fi

    # Register wallet and node if using wallet mode
    if [[ "$use_wallet" == true ]]; then
        log_info "Registering wallet: $wallet_addr"
        if ! "$DEFAULT_NEXUS_BIN" register-user --wallet-address "$wallet_addr"; then
            log_error "Failed to register wallet"
            exit 1
        fi
        
        log_info "Registering node..."
        if ! "$DEFAULT_NEXUS_BIN" register-node; then
            log_error "Failed to register node"
            exit 1
        fi
        
        local exec_cmd="$DEFAULT_NEXUS_BIN start --headless"
    else
        log_info "Using node ID: $node_id"
        local exec_cmd="$DEFAULT_NEXUS_BIN start --headless --node-id $node_id"
    fi

    # Create systemd service file
    create_systemd_service \
        "$SERVICE_FILE" \
        "$SERVICE_NAME" \
        "$exec_cmd" \
        "$DEFAULT_USER" \
        "$DEFAULT_WORK_DIR" \
        "Nexus Network Node"

    # Reload systemd and enable service
    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME"
    
    log_info "Service installed and enabled successfully"
    log_info "Run '$SCRIPT_NAME start' to launch the service"
}

install_logserver() {
    log_info "Installing Nexus Logserver service..."
    
    check_root
    
    # Stop and remove existing logserver if it exists
    if systemctl is-active --quiet "$LOGSERVER_NAME" 2>/dev/null; then
        log_warn "Stopping existing logserver..."
        sudo systemctl stop "$LOGSERVER_NAME" || true
    fi

    if systemctl is-enabled --quiet "$LOGSERVER_NAME" 2>/dev/null; then
        log_warn "Disabling existing logserver..."
        sudo systemctl disable "$LOGSERVER_NAME" || true
    fi

    # Create logserver script
    local logserver_script="/tmp/nexus-logserver.sh"
    cat > "$logserver_script" << 'EOF'
#!/bin/bash
set -euo pipefail

PORT="${1:-80}"
NEXUS_BIN="${2:-/root/.nexus/bin/nexus-network}"

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >&2
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Check if netcat is available
if ! command -v nc >/dev/null 2>&1; then
    log_error "netcat (nc) is required but not installed"
    exit 1
fi

log_info "Starting Nexus Logserver on port $PORT"

while true; do
    {
        echo -ne "HTTP/1.1 200 OK\r\n"
        echo -ne "Content-Type: text/plain; charset=utf-8\r\n"
        echo -ne "Connection: close\r\n"
        echo -ne "\r\n"
        echo "=== Nexus Network Status ==="
        echo "Timestamp: $(date)"
        echo ""
        
        if [[ -f "$NEXUS_BIN" ]]; then
            echo "Nexus Version: $($NEXUS_BIN --version 2>/dev/null || echo 'Unknown')"
        else
            echo "Nexus Binary: Not found at $NEXUS_BIN"
        fi
        echo ""
        
        echo "=== Service Status ==="
        systemctl status nexus-network --no-pager -l || echo "Service not running"
        echo ""
        
        echo "=== Recent Logs ==="
        journalctl -u nexus-network -n 10 --no-pager || echo "No logs available"
        
    } | nc -l -p "$PORT" -q 1 2>/dev/null || {
        log_error "Failed to bind to port $PORT. Port may be in use."
        sleep 5
    }
done
EOF

    chmod +x "$logserver_script"
    
    # Create systemd service for logserver
    create_systemd_service \
        "$LOGSERVER_FILE" \
        "$LOGSERVER_NAME" \
        "$logserver_script $DEFAULT_PORT $DEFAULT_NEXUS_BIN" \
        "$DEFAULT_USER" \
        "$DEFAULT_WORK_DIR" \
        "Nexus Log HTTP Server"

    # Reload systemd and enable logserver
    sudo systemctl daemon-reload
    sudo systemctl enable "$LOGSERVER_NAME"
    
    log_info "Logserver installed and enabled successfully"
    log_info "Run '$SCRIPT_NAME start-logserver' to launch the logserver"
}

# =============================================================================
# SERVICE CONTROL FUNCTIONS
# =============================================================================

start_service() {
    log_info "Starting $SERVICE_NAME service..."
    check_root
    
    if ! systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        log_error "Service $SERVICE_NAME is not installed. Run '$SCRIPT_NAME install' first."
        exit 1
    fi
    
    if sudo systemctl start "$SERVICE_NAME"; then
        log_info "Service started successfully"
    else
        log_error "Failed to start service"
        exit 1
    fi
}

stop_service() {
    log_info "Stopping $SERVICE_NAME service..."
    check_root
    
    if sudo systemctl stop "$SERVICE_NAME"; then
        log_info "Service stopped successfully"
    else
        log_warn "Service may not have been running"
    fi
}

restart_service() {
    log_info "Restarting $SERVICE_NAME service..."
    check_root
    
    if ! systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        log_error "Service $SERVICE_NAME is not installed. Run '$SCRIPT_NAME install' first."
        exit 1
    fi
    
    if sudo systemctl restart "$SERVICE_NAME"; then
        log_info "Service restarted successfully"
    else
        log_error "Failed to restart service"
        exit 1
    fi
}

show_status() {
    log_info "Checking $SERVICE_NAME service status..."
    sudo systemctl status "$SERVICE_NAME" --no-pager -l
}

show_logs() {
    local lines="${1:-50}"
    log_info "Showing last $lines lines of $SERVICE_NAME service logs..."
    journalctl -u "$SERVICE_NAME" -n "$lines" --no-pager
}

remove_service() {
    log_info "Removing $SERVICE_NAME service..."
    check_root
    
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        log_warn "Stopping service..."
        sudo systemctl stop "$SERVICE_NAME" || true
    fi
    
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        log_warn "Disabling service..."
        sudo systemctl disable "$SERVICE_NAME" || true
    fi
    
    if [[ -f "$SERVICE_FILE" ]]; then
        sudo rm -f "$SERVICE_FILE"
        sudo systemctl daemon-reload
        log_info "Service removed successfully"
    else
        log_warn "Service file not found: $SERVICE_FILE"
    fi
}

# =============================================================================
# LOGSERVER CONTROL FUNCTIONS
# =============================================================================

start_logserver() {
    log_info "Starting $LOGSERVER_NAME service..."
    check_root
    
    if ! systemctl is-enabled --quiet "$LOGSERVER_NAME" 2>/dev/null; then
        log_error "Logserver $LOGSERVER_NAME is not installed. Run '$SCRIPT_NAME install-logserver' first."
        exit 1
    fi
    
    if sudo systemctl start "$LOGSERVER_NAME"; then
        log_info "Logserver started successfully on port $DEFAULT_PORT"
    else
        log_error "Failed to start logserver"
        exit 1
    fi
}

stop_logserver() {
    log_info "Stopping $LOGSERVER_NAME service..."
    check_root
    
    if sudo systemctl stop "$LOGSERVER_NAME"; then
        log_info "Logserver stopped successfully"
    else
        log_warn "Logserver may not have been running"
    fi
}

show_logserver_logs() {
    local lines="${1:-50}"
    log_info "Showing last $lines lines of $LOGSERVER_NAME service logs..."
    journalctl -u "$LOGSERVER_NAME" -n "$lines" --no-pager
}

remove_logserver() {
    log_info "Removing $LOGSERVER_NAME service..."
    check_root
    
    if systemctl is-active --quiet "$LOGSERVER_NAME" 2>/dev/null; then
        log_warn "Stopping logserver..."
        sudo systemctl stop "$LOGSERVER_NAME" || true
    fi
    
    if systemctl is-enabled --quiet "$LOGSERVER_NAME" 2>/dev/null; then
        log_warn "Disabling logserver..."
        sudo systemctl disable "$LOGSERVER_NAME" || true
    fi
    
    if [[ -f "$LOGSERVER_FILE" ]]; then
        sudo rm -f "$LOGSERVER_FILE"
        sudo systemctl daemon-reload
        log_info "Logserver removed successfully"
    else
        log_warn "Logserver file not found: $LOGSERVER_FILE"
    fi
}

# =============================================================================
# HELP AND USAGE FUNCTIONS
# =============================================================================

show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME <command> [options]

COMMANDS:
    install [--node-id <id> | --wallet <wallet-address>]
        Install and configure the Nexus Network service
        --node-id <id>        Use specific node ID (required if not using wallet)
        --wallet <address>    Use wallet address for registration (required if not using node-id)

    start                     Start the Nexus Network service
    stop                      Stop the Nexus Network service
    restart                   Restart the Nexus Network service
    status                    Show service status
    logs [lines]              Show service logs (default: 50 lines)
    remove                    Remove the Nexus Network service

    install-logserver         Install the logserver service
    start-logserver           Start the logserver service
    stop-logserver            Stop the logserver service
    logs-logserver [lines]    Show logserver logs (default: 50 lines)
    remove-logserver          Remove the logserver service

    help                      Show this help message

EXAMPLES:
    $SCRIPT_NAME install --wallet 0x1234567890abcdef1234567890abcdef12345678
    $SCRIPT_NAME install --node-id 12345
    $SCRIPT_NAME start
    $SCRIPT_NAME logs 100
    $SCRIPT_NAME install-logserver
    $SCRIPT_NAME start-logserver

EOF
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Check if at least one argument is provided
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 1
    fi

    local command="$1"
    shift

    case "$command" in
        install)
            install_service "$@"
            ;;
        start)
            start_service
            ;;
        stop)
            stop_service
            ;;
        restart)
            restart_service
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs "${1:-50}"
            ;;
        remove)
            remove_service
            ;;
        install-logserver)
            install_logserver
            ;;
        start-logserver)
            start_logserver
            ;;
        stop-logserver)
            stop_logserver
            ;;
        logs-logserver)
            show_logserver_logs "${1:-50}"
            ;;
        remove-logserver)
            remove_logserver
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Execute main function with all arguments
main "$@"