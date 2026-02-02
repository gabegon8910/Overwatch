# Overwatch

Agentless server management platform for monitoring, log collection, and script execution across mixed Linux and Windows environments.

![License](https://img.shields.io/badge/license-proprietary-blue)
![Version](https://img.shields.io/badge/version-2.2.3-green)
![Docker](https://img.shields.io/badge/docker-compose-blue)

## Features

### Free Tier
- **Server Monitoring** — CPU, memory, disk, network metrics via SSH/WinRM (no agents required)
- **Log Collection** — Aggregate logs from all servers with search and filtering
- **Script Execution** — Run Bash, PowerShell, and Python scripts with scheduling
- **Alert Rules** — Threshold-based alerts with email, Discord, Slack, and webhook notifications
- **Maintenance Mode** — Suppress alerts during scheduled maintenance windows
- **Credential Vault** — Encrypted storage for SSH keys and passwords
- **Browser Console** — Browser-based RDP/SSH via Apache Guacamole
- **Multi-datacenter** — Organize servers by datacenter and groups
- **RBAC** — Role-based access control with admin/operator/viewer roles
- **API Keys** — Programmatic access for automation and integrations

### Pro License
- **Secrets Vault** — Centralized encrypted secrets with `$SECRET{/path}` injection into scripts and audit trail
- **Vulnerability Scanning** — Automated CVE detection via OSV.dev for installed packages
- **Agent Mode** — Lightweight Python agent for servers behind firewalls (phones home via HTTPS)

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/gabegon8910/Overwatch/main/install.sh | bash
```

The installer will:
1. Check for Docker and Docker Compose
2. Download the docker-compose.yml
3. Generate secure random secrets
4. Prompt for your public URL
5. Start all containers

Then open the URL shown in your browser to create your admin account.

## Manual Installation

```bash
# Download files
mkdir ~/overwatch && cd ~/overwatch
curl -fsSL https://raw.githubusercontent.com/gabegon8910/Overwatch/main/docker-compose.yml -o docker-compose.yml
curl -fsSL https://raw.githubusercontent.com/gabegon8910/Overwatch/main/.env.example -o .env

# Edit .env — you MUST set these:
#   SECRET_KEY        — openssl rand -hex 32
#   ENCRYPTION_KEY    — openssl rand -hex 16
#   POSTGRES_PASSWORD — openssl rand -hex 16
#   FRONTEND_URL      — your server's public URL
nano .env

# Start
docker compose up -d
```

## Upgrading

```bash
cd ~/overwatch

# Pull new version and restart
VERSION=2.2.3 docker compose pull
VERSION=2.2.3 docker compose up -d
```

To pin a specific version, set `VERSION=2.2.3` in your `.env` file.

## Rolling Back

```bash
VERSION=2.2.2 docker compose up -d
```

## Configuration

All configuration is done via the `.env` file. See [`.env.example`](.env.example) for all options.

| Variable | Required | Description |
|---|---|---|
| `SECRET_KEY` | Yes | JWT signing key (`openssl rand -hex 32`) |
| `ENCRYPTION_KEY` | Yes | Credential encryption key (`openssl rand -hex 16`) |
| `POSTGRES_PASSWORD` | Yes | Database password |
| `FRONTEND_URL` | Yes | Public URL (e.g. `https://overwatch.example.com`) |
| `HTTP_PORT` | No | Web UI port (default: `80`) |
| `VERSION` | No | Image version tag (default: `latest`) |
| `LICENSE_KEY` | No | Pro license key (leave empty for free tier) |

## Architecture

```
                    ┌──────────────┐
                    │   Frontend   │ :80
                    │   (nginx)    │
                    └──────┬───────┘
                           │
                    ┌──────┴───────┐
                    │   Backend    │ :8000
                    │  (FastAPI)   │
                    └──┬───────┬───┘
                       │       │
              ┌────────┘       └────────┐
              │                         │
       ┌──────┴───────┐        ┌───────┴──────┐
       │  PostgreSQL   │        │    Redis     │
       │   (data)      │        │  (cache/mq)  │
       └───────────────┘        └───────┬──────┘
                                        │
                              ┌─────────┴─────────┐
                              │  Celery Worker(s)  │
                              │  Celery Beat       │
                              └────────────────────┘
```

**Containers:**
| Container | Purpose |
|---|---|
| `ssm-frontend` | Web UI (nginx reverse proxy) |
| `ssm-backend` | REST API (FastAPI + Uvicorn) |
| `ssm-celery-worker` | Background tasks (metric collection, script execution) |
| `ssm-celery-beat` | Scheduled tasks (alert checks, maintenance windows) |
| `ssm-postgres` | Database |
| `ssm-redis` | Cache, message broker, real-time events |
| `ssm-guacd` | Guacamole proxy daemon (browser RDP/SSH) |
| `ssm-guacamole` | Guacamole web application |

## Agent Mode (Pro)

For servers where inbound SSH/WinRM is blocked, install the lightweight agent that phones home via HTTPS.

### Install

In the Overwatch UI, go to **Server Detail > Agent** and click **Generate Token**. Then on the target server:

```bash
curl -fsSL https://raw.githubusercontent.com/gabegon8910/Overwatch/main/agent/install.sh | bash -s -- \
  --url https://overwatch.example.com \
  --token YOUR_AGENT_TOKEN
```

### What it does

- Sends heartbeat every 30 seconds
- Pushes CPU, memory, disk, network metrics
- Polls for and executes pending scripts
- Runs as a systemd service (`overwatch-agent`)
- Single Python file, minimal dependencies (`psutil`, `requests`)

### Management

```bash
systemctl status overwatch-agent    # Check status
journalctl -u overwatch-agent -f    # View logs
systemctl restart overwatch-agent   # Restart
systemctl stop overwatch-agent      # Stop
```

## Terraform Provider

Manage Overwatch resources as Infrastructure as Code. See the [terraform-provider-overwatch](https://github.com/gabegon8910/terraform-provider-overwatch) repository.

```hcl
provider "overwatch" {
  host    = "https://overwatch.example.com"
  api_key = var.overwatch_api_key
}

resource "overwatch_server" "web" {
  name       = "web-prod-01"
  hostname   = "web-prod-01.example.com"
  ip_address = "10.0.1.10"
  os_type    = "LINUX"
  datacenter = "us-east-1"
}
```

## System Requirements

| Scale | Servers | CPU | RAM | Disk |
|---|---|---|---|---|
| Small | 1–25 | 2 vCPU | 4 GB | 40 GB SSD |
| Medium | 25–100 | 4 vCPU | 8 GB | 100 GB SSD |
| Large | 100–500 | 8 vCPU | 16 GB | 250 GB SSD |

Storage grows at approximately 50 MB per server per month at default collection intervals.

### Network Requirements

- **Outbound from Overwatch**: SSH (22) and/or WinRM (5985/5986) to managed servers
- **Inbound to Overwatch**: HTTP/HTTPS for the web UI and API
- **Agent mode**: Only requires HTTPS outbound from the managed server to Overwatch

## Backups

Database backups can be created via the UI or API. Backup files are stored in the `backend_backups` Docker volume.

To create a manual backup:
```bash
docker exec ssm-postgres pg_dump -U ssm_user ssm_db | gzip > overwatch-backup-$(date +%Y%m%d).sql.gz
```

To restore:
```bash
gunzip -c overwatch-backup-20250201.sql.gz | docker exec -i ssm-postgres psql -U ssm_user ssm_db
```

## Security Notes

- Change all default secrets in `.env` before production use
- Use a reverse proxy (nginx, Caddy, Traefik) with TLS for HTTPS
- The backend container runs as a non-root user with a read-only filesystem
- Registration auto-locks after the first admin account is created
- Set `CORS_ORIGINS` in your `.env` to restrict API access to your domain

## Useful Commands

```bash
# View all container status
docker compose ps

# Follow logs
docker compose logs -f
docker compose logs -f backend       # Backend only

# Restart a single service
docker compose restart backend

# Stop everything
docker compose down

# Stop and remove all data (destructive!)
docker compose down -v
```

## License

Proprietary. Free tier available for unlimited use. Pro features require a license key from [byteforce.us](https://byteforce.us).

## Support

- Issues: [GitHub Issues](https://github.com/gabegon8910/Overwatch/issues)
- Email: support@byteforce.us
