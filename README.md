# Nexus Service Script

A comprehensive service management script for Nexus Network nodes and logserver. This script provides installation, configuration, and lifecycle management for systemd services with improved error handling, validation, and logging.

## Features

- **Service Management**: Install, start, stop, restart, and remove Nexus Network services
- **Logserver Support**: HTTP-based status monitoring on port 80
- **Input Validation**: Wallet address and node ID validation
- **Error Handling**: Comprehensive error checking and user-friendly messages
- **Security**: Enhanced systemd service configurations with security settings
- **Logging**: Structured logging with different levels (INFO, WARN, ERROR)
- **Flexibility**: Support for both wallet-based and node-ID-based configurations

## Usage

### Basic Commands

```bash
# Install service with wallet address
./nexus-service.sh install --wallet 0x1234567890abcdef1234567890abcdef12345678

# Install service with node ID
./nexus-service.sh install --node-id 12345

# Install with max-difficulty setting
./nexus-service.sh install --wallet 0x1234567890abcdef1234567890abcdef12345678 --max-difficulty MEDIUM
./nexus-service.sh install --node-id 12345 --max-difficulty LARGE

# Service control
./nexus-service.sh start
./nexus-service.sh stop
./nexus-service.sh restart
./nexus-service.sh status
./nexus-service.sh logs [lines]

# Remove service
./nexus-service.sh remove
```

### Logserver Commands

```bash
# Install and manage logserver
./nexus-service.sh install-logserver
./nexus-service.sh start-logserver
./nexus-service.sh stop-logserver
./nexus-service.sh logs-logserver [lines]
./nexus-service.sh remove-logserver
```

### Help

```bash
./nexus-service.sh help
```

## GCP Startup Script

For automated deployment on Google Cloud Platform:

```bash
#!/bin/bash
# GCP VM Startup Script for Nexus Node + Logserver

set -euxo pipefail
export SHELL=/bin/bash
export HOME=/root

# Update & install dependencies
apt-get update -y
apt-get install -y curl netcat-openbsd

# Install Nexus CLI
cd /root
rm -rf .nexus
rm -rf *
curl -sSf https://cli.nexus.xyz/ -o install.sh
chmod +x install.sh
NONINTERACTIVE=1 /root/install.sh

# Download nexus-service.sh wrapper
mkdir -p /root/.nexus
curl -fsSL \
  https://raw.githubusercontent.com/monkey-mode/nexus-service-script/main/nexus-service.sh \
  -o /root/.nexus/nexus-service.sh
chmod +x /root/.nexus/nexus-service.sh

# Remove old services if they exist
/root/.nexus/nexus-service.sh stop || true
/root/.nexus/nexus-service.sh remove || true
/root/.nexus/nexus-service.sh stop-logserver || true
/root/.nexus/nexus-service.sh remove-logserver || true

# Install and start the nexus network service
# Replace with your actual wallet address or node ID
/root/.nexus/nexus-service.sh install --wallet YOUR_WALLET_ADDRESS_HERE
# OR use node ID: /root/.nexus/nexus-service.sh install --node-id YOUR_NODE_ID_HERE
# Optional: add max-difficulty: --max-difficulty MEDIUM
/root/.nexus/nexus-service.sh start

# Install and start the logserver (HTTP on port 80)
/root/.nexus/nexus-service.sh install-logserver
/root/.nexus/nexus-service.sh start-logserver
```

## Configuration

The script uses the following default values:

- **Service Name**: `nexus-network`
- **Logserver Name**: `nexus-logserver`
- **HTTP Port**: `80`
- **Nexus Binary Path**: `/root/.nexus/bin/nexus-network`

**Required Parameters:**
- Either `--node-id <id>` or `--wallet <address>` must be provided when installing the service

**Optional Parameters:**
- `--max-difficulty <level>`: Set the maximum task difficulty level
  - Valid values: `SMALL`, `SMALL_MEDIUM`, `MEDIUM`, `LARGE`, `EXTRA_LARGE`, `EXTRA_LARGE2`
  - If not specified, the service will use the default difficulty setting

## Security Features

- Input validation for wallet addresses and node IDs
- Enhanced systemd service configurations with security settings
- Proper privilege management
- Error handling and logging

## Requirements

- Linux system with systemd
- Root privileges or sudo access
- Nexus CLI installed
- netcat (for logserver functionality)

## Error Handling

The script includes comprehensive error handling:
- Validates wallet address format (0x + 40 hex characters)
- Validates node ID format (numeric)
- Checks for required binaries and permissions
- Provides clear error messages and suggestions