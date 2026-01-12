# agent-init
## Minimum requirements
  💾  Disk Size: 2 GB
  🧠  CPU Cores: 1
  🛠️  RAM Size: 512 MiB

## Getting Started

create an `.env` file with the following details in your current directory

This will be moved into the `/opt/techtoday-agent`

```
DOMAIN_NAME=http://localhost
# AI/LLM Configuration
OPENAI_API_KEY=
# Authentication & API Tokens
ADMIN_EMAIL=admin@admin.com
# API key for currency information from data.fixer.io
LICENSE_KEY=
CONTROL_URL=
#github
GITHUB_USERNAME=
GITHUB_PAT=
```

Init for Agent docekr images

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Skulldorom/agent-init/refs/heads/main/init.sh)"
```

## Updating the Services

After initial setup, you can update your services to the latest versions by simply running:

```
update
```

This command can be run from anywhere and will:
- **Check for updates to the update script itself** and apply them automatically
- Stop all Docker services
- Download the latest configuration files (docker-compose.yml, nginx.conf)
- Pull the latest Docker images
- **Clean up old and unused Docker images** to free up disk space
- Restart all services

The update command now includes:
- **Self-update capability**: The update script checks for its own updates and automatically applies them before proceeding
- **Docker image cleanup**: Removes dangling and old unused images (older than 24 hours) to prevent disk space issues

