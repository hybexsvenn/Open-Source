#!/usr/bin/env bash
set -euo pipefail

echo "=== Steg 1: Systemuppdatering ==="
sudo apt-get update
sudo apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release

echo "=== Steg 2: Installera Docker & docker-compose ==="
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-compose-plugin

########################################
echo "=== Steg 3: LITELLM ==="
########################################
mkdir -p ~/litellm && cd ~/litellm

cat > .env <<EOF
LITELLM_MASTER_KEY="sk-1234"
LITELLM_SALT_KEY="sk-1234"
SERVER_ROOT_PATH="/litellm2"
STORE_MODEL_IN_DB="True"
EOF

cat > litellm_config.yaml <<EOF
general_settings:
  master_key: sk-1234
  database_url: postgresql://llmproxy:dbpass@db:5432/litellm
model_list: []
EOF

cat > docker-compose.yml <<'EOF'
version: "3.9"
services:
  db:
    image: postgres:16
    restart: always
    environment:
      POSTGRES_DB: litellm
      POSTGRES_USER: llmproxy
      POSTGRES_PASSWORD: dbpass
    volumes:
      - postgres_data:/var/lib/postgresql/data

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    depends_on:
      - db
    ports:
      - "4000:4000"
    env_file:
      - .env
    volumes:
      - ./litellm_config.yaml:/app/config.yaml
    command: ["--config", "/app/config.yaml", "--port", "4000"]

volumes:
  postgres_data:
EOF

docker compose up -d

########################################
echo "=== Steg 4: Nginx Proxy Manager ==="
########################################
mkdir -p ~/nginx-proxy-manager && cd ~/nginx-proxy-manager

cat > docker-compose.yml <<'EOF'
version: "3.8"
services:
  app:
    image: jc21/nginx-proxy-manager:latest
    restart: always
    ports:
      - "80:80"
      - "81:81"
      - "443:443"
    environment:
      DB_MYSQL_HOST: "db"
      DB_MYSQL_PORT: 3306
      DB_MYSQL_USER: "npm"
      DB_MYSQL_PASSWORD: "npm"
      DB_MYSQL_DATABASE: "npm"
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt

  db:
    image: jc21/mariadb-aria:latest
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: "npm"
      MYSQL_DATABASE: "npm"
      MYSQL_USER: "npm"
      MYSQL_PASSWORD: "npm"
    volumes:
      - ./data/mysql:/var/lib/mysql

volumes:
  data:
  letsencrypt:
EOF

docker compose up -d

########################################
echo "=== Steg 5: Open WebUI ==="
########################################
mkdir -p ~/open-webui && cd ~/open-webui

cat > docker-compose.yml <<'EOF'
version: "3"
services:
  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    ports:
      - "3000:8080"
    volumes:
      - open-webui:/app/backend/data

volumes:
  open-webui:
EOF

docker compose up -d

########################################
echo "=== Steg 6: n8n ==="
########################################
mkdir -p ~/n8n && cd ~/n8n

cat > docker-compose.yml <<'EOF'
version: "3.8"
services:
  postgres:
    image: postgres:13
    restart: unless-stopped
    environment:
      POSTGRES_DB: n8n
      POSTGRES_USER: n8n
      POSTGRES_PASSWORD: n8n_password  # Ändra till ett starkt lösenord!
    volumes:
      - postgres_data:/var/lib/postgresql/data

  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: n8n
      DB_POSTGRESDB_USER: n8n
      DB_POSTGRESDB_PASSWORD: n8n_password

      N8N_BASIC_AUTH_ACTIVE: "true"
      N8N_BASIC_AUTH_USER: n8nadmin
      N8N_BASIC_AUTH_PASSWORD: admin_password  # Ändra till ett starkt lösenord!

      # WEBHOOK_TUNNEL_URL: "https://n8n.example.com/"

      GENERIC_TIMEZONE: "Europe/Stockholm"

    depends_on:
      - postgres
    volumes:
      - n8n_data:/home/node/.n8n

volumes:
  postgres_data:
  n8n_data:
EOF

docker compose up -d

echo "✔️ Alla tjänster är nu igång!"
