#!/bin/bash

# Exit on any error
set -e


echo "======================================"
echo "Server Setup Script"
echo "======================================"

# ====================================
# LOAD ENVIRONMENT VARIABLES 
# ====================================

ENV_FILE=".env"
PROJECT_DIR="/opt/techtoday-agent"
REPO_URL="https://github.com/Skulldorom/agent-init"
REPO_BRANCH="main"
echo "checking env file...."

# Check for .env file in current directory first
if [ ! -f "$ENV_FILE" ]; then
    # If not found in current directory, check if it exists in the project directory
    if [ -d "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/.env" ]; then
        echo "✓ Found .env file in $PROJECT_DIR (from previous installation)"
        echo "  Using existing .env file from project directory"
        ENV_FILE="$PROJECT_DIR/.env"
    else
        echo ""
        echo "✗ ERROR: .env file not found at $ENV_FILE"
        echo ""
        echo "Please create your .env file first with all required variables:"
        echo "  nano $ENV_FILE"
        echo ""
        echo "Required variables:"
        echo "  GITHUB_PAT=ghp_your_token_here"
        echo "  GITHUB_USERNAME=your_username"
        echo ""
        echo "Add any other environment variables your app needs."
        echo ""
        exit 1
    fi
fi

#create project directory
mkdir -p "$PROJECT_DIR"
chmod 700 "$PROJECT_DIR"

echo "Loading environment variables from $ENV_FILE..."

#add automated secret_key and encryption key if they don't exist
if ! grep -q "^SECRET_KEY=" "$ENV_FILE"; then
    echo "SECRET_KEY=$(openssl rand -hex 32)" >> "$ENV_FILE"
    echo "✓ SECRET_KEY added!"
else
    echo "✓ SECRET_KEY already exists"
fi

if ! grep -q "^ENCRYPTION_KEY=" "$ENV_FILE"; then
    echo "ENCRYPTION_KEY=$(openssl rand -base64 32)" >> "$ENV_FILE"
    echo "✓ ENCRYPTION_KEY added!"
else
    echo "✓ ENCRYPTION_KEY already exists"
fi
if ! grep -q "^POSTGRES_USER=" "$ENV_FILE"; then
    echo "POSTGRES_USER=\"$(openssl rand -hex 16)\"" >> "$ENV_FILE"
    echo "✓ POSTGRES_USER added!"
else
    echo "✓ POSTGRES_USER already exists"
fi

if ! grep -q "^POSTGRES_PASSWORD=" "$ENV_FILE"; then
    echo "POSTGRES_PASSWORD=\"$(openssl rand -hex 16)\"" >> "$ENV_FILE"
    echo "✓ POSTGRES_PASSWORD added!"
else
    echo "✓ POSTGRES_PASSWORD already exists"
fi

if ! grep -q "^DAILY_REPORT_SECRET=" "$ENV_FILE"; then
    echo "DAILY_REPORT_SECRET=\"$(openssl rand -base64 32)\"" >> "$ENV_FILE"
    echo "✓ DAILY_REPORT_SECRET added!"
else
    echo "✓ DAILY_REPORT_SECRET already exists"
fi

if ! grep -q "^ADMIN_PASSWORD=" "$ENV_FILE"; then
    ADMIN_PASSWORD="$(openssl rand -base64 16)"
    echo "ADMIN_PASSWORD=\"$ADMIN_PASSWORD\"" >> "$ENV_FILE"
    echo "✓ ADMIN_PASSWORD added!"
else
    # Extract existing password from the file
    ADMIN_PASSWORD=$(grep "^ADMIN_PASSWORD=" "$ENV_FILE" | cut -d'"' -f2)
    echo "✓ ADMIN_PASSWORD already exists"
fi



# Load environment variables from .env
set -a  # automatically export all variables
source "$ENV_FILE"
set +a

echo "✓ Environment variables loaded"


if [ -z "$GITHUB_PAT" ] || [ -z "$GITHUB_USERNAME" ]; then
    echo "✗ ERROR: GITHUB_PAT and GITHUB_USERNAME must be set in .env file"
    exit 1
fi

# Set proper permissions on .env
chmod 600 "$ENV_FILE"


# ====================================
# 1. Install Docker
# ====================================
echo ""
echo "[1/3] Installing Docker..."

if command -v docker &> /dev/null; then
    echo "✓ Docker already installed ($(docker --version))"
else
    # Install Docker using official script
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    
    # Add current user to docker group
    usermod -aG docker $USER
    
    echo "✓ Docker installed"
fi

# Install Docker Compose plugin
if ! docker compose version &> /dev/null; then
    echo "Installing Docker Compose..."
    apt-get update
    apt-get install -y docker-compose-plugin
fi

echo "✓ Docker Compose ready ($(docker compose version))"

# ====================================
# 2. Login to GitHub Container Registry
# ====================================
echo ""
echo "[2/3] Logging into GitHub Container Registry..."

echo "$GITHUB_PAT" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin
echo "✓ Logged into ghcr.io as $GITHUB_USERNAME"

# Also login to docker.pkg.github.com (legacy GitHub Packages)
echo "$GITHUB_PAT" | docker login docker.pkg.github.com -u "$GITHUB_USERNAME" --password-stdin
echo "✓ Logged into docker.pkg.github.com"

# ====================================
# 5. Setup Docker Compose
# ====================================
echo ""
echo "[3/3] Setting up Docker Compose..."

# Download repository files
echo "Downloading repository files..."
TEMP_DIR=$(mktemp -d)
if curl -fsSL "${REPO_URL}/archive/refs/heads/${REPO_BRANCH}.tar.gz" | tar -xz -C "$TEMP_DIR" --strip-components=1; then
    echo "✓ Repository files downloaded"
    
    # Copy necessary files to project directory
    if [ -f "$TEMP_DIR/docker-compose.yml" ]; then
        cp "$TEMP_DIR/docker-compose.yml" "$PROJECT_DIR/"
    else
        echo "✗ Error: docker-compose.yml not found in repository"
        [ -n "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    if [ -f "$TEMP_DIR/nginx.conf" ]; then
        cp "$TEMP_DIR/nginx.conf" "$PROJECT_DIR/"
    else
        echo "✗ Error: nginx.conf not found in repository"
        [ -n "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Install update script
    if [ -f "$TEMP_DIR/update.sh" ]; then
        cp "$TEMP_DIR/update.sh" /usr/local/bin/update
        chmod +x /usr/local/bin/update
        echo "✓ update script installed (run 'update' from anywhere to update services)"
    fi
    
    # Clean up temp directory
    [ -n "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
else
    echo "✗ Error: Could not download repository from $REPO_URL"
    [ -n "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
    exit 1
fi

echo "moving env to project directory.."
#move env file to project directory (if it's not already there)
if [ "$ENV_FILE" != "$PROJECT_DIR/.env" ]; then
    mv "$ENV_FILE" "$PROJECT_DIR/.env"
fi
cd "$PROJECT_DIR"

# Start services
docker compose up -d

echo "✓ Docker services started"


# initialize database

echo "Initializing db..."
if curl -k --fail --retry 4 --retry-delay 2 --retry-connrefused --retry-all-errors \
  -X POST "https://localhost/api/init" \
  -H "Host: ${DOMAIN_NAME:-yourdomain.com}"; then
    echo "Backend initialized"
else
    echo "Failed to initialize backend, manual post request to https://localhost/api/init required"
fi
# ====================================
# Done
# ====================================
echo ""
echo "======================================"
echo "✓ Setup Complete!"
echo "======================================"
echo ""
echo -e "🌐 Your application is now live at:"
echo -e "   \033[1;34m${DOMAIN_NAME}\033[0m"
echo ""
echo -e "🌐 Your admin email is $ADMIN_EMAIL and password is $ADMIN_PASSWORD:"
echo "Manage services with:"
echo "   - docker compose ps      (view status)"
echo "   - docker compose logs    (view logs)"
echo "   - docker compose down    (stop services)"
echo "   - docker compose pull    (update images)"
echo "   - docker compose restart (restart services)"
echo ""
echo "Quick update command:"
echo "   - update                 (stops services, downloads new files, pulls new images, and restarts)"
echo ""
echo "NOTE: If Docker was just installed, log out and back in for group changes to take effect"
echo ""
