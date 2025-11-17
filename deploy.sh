#!/bin/bash
set -euo pipefail

echo "===== Pixel River Financial - Automated Deployment ====="

#######################################
# 1. PRE-DEPLOYMENT CHECKS
#######################################

echo ">> Checking required commands..."

check_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: '$1' is not installed or not in PATH."
    exit 1
  fi
}

check_command docker

# Support both 'docker compose' and 'docker-compose'
if command -v docker compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  echo "ERROR: Docker Compose is not installed."
  exit 1
fi

echo ">> Docker and Docker Compose found."

#######################################
# 2. PORT AVAILABILITY CHECK
#######################################

PORTS=(3000 5000 80)

echo ">> Checking if required ports are free: ${PORTS[*]}"

for P in "${PORTS[@]}"; do
  if command -v lsof >/dev/null 2>&1; then
    if lsof -i:"$P" >/dev/null 2>&1; then
      echo "ERROR: Port $P is already in use. Free it and run again."
      exit 1
    fi
  else
    echo "NOTE: 'lsof' not available, skipping strict port check for $P."
  fi
done

#######################################
# 3. VALIDATE docker-compose.yaml
#######################################

echo ">> Validating docker-compose.yaml presence..."

if [ ! -f "docker-compose.yaml" ] && [ ! -f "docker-compose.yml" ]; then
  echo "ERROR: docker-compose.yaml or docker-compose.yml not found in $(pwd)"
  exit 1
fi

COMPOSE_FILE="docker-compose.yaml"
[ -f "docker-compose.yml" ] && COMPOSE_FILE="docker-compose.yml"

echo ">> Using compose file: $COMPOSE_FILE"

#######################################
# 4. BUILD & DEPLOY
#######################################

echo ">> Bringing down any existing containers..."
$COMPOSE_CMD -f "$COMPOSE_FILE" down -v || true

echo ">> Building images..."
$COMPOSE_CMD -f "$COMPOSE_FILE" build

echo ">> Starting containers in detached mode..."
$COMPOSE_CMD -f "$COMPOSE_FILE" up -d

#######################################
# 5. HEALTH CHECKS
#######################################

echo ">> Waiting a few seconds for services to start..."
sleep 5

echo ">> Running health check on backend (http://localhost:5000)..."
curl -f http://localhost:5000 >/dev/null 2>&1
echo "   Backend is responding."

echo ">> Running health check on frontend (http://localhost:3000)..."
curl -f http://localhost:3000 >/dev/null 2>&1
echo "   Frontend is responding."

#######################################
# 6. SHOW docker ps & CAPTURE NGINX CONTAINER ID
#######################################

echo ">> Current running containers:"
docker ps

echo ">> Capturing nginx container ID..."
NGINX_CONTAINER_ID=$(docker ps --filter "ancestor=nginx:alpine" --format "{{.ID}}" | head -n 1)

if [ -z "$NGINX_CONTAINER_ID" ]; then
  # fallback: try image/name contains 'nginx'
  NGINX_CONTAINER_ID=$(docker ps --format "{{.ID}} {{.Image}}" | grep -i nginx | awk '{print $1}' | head -n 1)
fi

if [ -z "$NGINX_CONTAINER_ID" ]; then
  echo "WARNING: Could not find nginx container ID."
else
  echo "   NGINX_CONTAINER_ID=$NGINX_CONTAINER_ID"
fi

#######################################
# 7. VALIDATE PAGE RENDERS VIA NGINX
#######################################

echo ">> Checking main URL via nginx (http://localhost)..."
curl -f http://localhost >/dev/null 2>&1
echo "   Main URL is responding through nginx."

#######################################
# 8. ENSURE jq INSTALLED
#######################################

echo ">> Ensuring 'jq' is installed..."

if ! command -v jq >/dev/null 2>&1; then
  echo "   'jq' not found. Installing via apt..."
  sudo apt update && sudo apt install -y jq
else
  echo "   'jq' is already installed."
fi

#######################################
# 9. INSPECT nginx:alpine IMAGE
#######################################

NGINX_IMAGE="nginx:alpine"

echo ">> Inspecting image $NGINX_IMAGE ..."
docker inspect "$NGINX_IMAGE" > nginx-logs.txt

echo "   nginx-logs.txt created."

#######################################
# 10. EXTRACT REQUIRED FIELDS WITH jq
#######################################

echo "===== Extracted Values from $NGINX_IMAGE ====="

echo "RepoTags:"
jq '.[0].RepoTags' nginx-logs.txt || echo "   (Could not read RepoTags)"

echo
echo "Created:"
jq '.[0].Created' nginx-logs.txt || echo "   (Could not read Created)"

echo
echo "Os:"
jq '.[0].Os' nginx-logs.txt || echo "   (Could not read Os)"

echo
echo "Config:"
jq '.[0].Config' nginx-logs.txt || echo "   (Could not read Config)"

echo
echo "ExposedPorts:"
jq '.[0].Config.ExposedPorts' nginx-logs.txt || echo "   (Could not read ExposedPorts)"

echo
echo "===== Deployment Script Completed Successfully ====="
