#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  pgwatch-ai — Instalação inicial
#
#  Uso:
#    curl -fsSL https://raw.githubusercontent.com/wislanmoraes/pgwatchai-client/main/install.sh | bash
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

BASE_URL="https://raw.githubusercontent.com/wislanmoraes/pgwatchai-client/main"
INSTALL_DIR="${PGWATCH_DIR:-$HOME/pgwatchai}"

GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; CYAN="\033[0;36m"; RESET="\033[0m"
info()    { echo -e "${GREEN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
section() { echo -e "\n${CYAN}━━━ $* ${RESET}"; }

# ── Banner ────────────────────────────────────────────────────────────────────

echo -e "${CYAN}"
echo "  ██████╗  ██████╗ ██╗    ██╗ █████╗ ████████╗ ██████╗██╗  ██╗      █████╗ ██╗"
echo "  ██╔══██╗██╔════╝ ██║    ██║██╔══██╗╚══██╔══╝██╔════╝██║  ██║     ██╔══██╗██║"
echo "  ██████╔╝██║  ███╗██║ █╗ ██║███████║   ██║   ██║     ███████║     ███████║██║"
echo "  ██╔═══╝ ██║   ██║██║███╗██║██╔══██║   ██║   ██║     ██╔══██║     ██╔══██║██║"
echo "  ██║     ╚██████╔╝╚███╔███╔╝██║  ██║   ██║   ╚██████╗██║  ██║     ██║  ██║██║"
echo "  ╚═╝      ╚═════╝  ╚══╝╚══╝ ╚═╝  ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝     ╚═╝  ╚═╝╚═╝"
echo -e "${RESET}"
echo -e "  Instalação inicial — PostgreSQL Monitoring with AI\n"

# ── Pré-requisitos ────────────────────────────────────────────────────────────

section "Verificando pré-requisitos"

for cmd in docker curl; do
  if ! command -v "$cmd" &>/dev/null; then
    error "$cmd não encontrado. Instale antes de continuar."
    exit 1
  fi
  info "$cmd ✓"
done

if ! docker compose version &>/dev/null; then
  error "Docker Compose plugin não encontrado."
  error "Execute: apt install docker-compose-plugin  (Debian/Ubuntu)"
  error "         yum install docker-compose-plugin  (RHEL/AlmaLinux)"
  exit 1
fi
info "docker compose ✓"

if ! docker info &>/dev/null; then
  error "Docker daemon não está rodando ou sem permissão."
  error "Execute: systemctl start docker"
  exit 1
fi
info "docker daemon ✓"

# ── Diretório de instalação ───────────────────────────────────────────────────

section "Preparando diretório"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
info "Diretório: $INSTALL_DIR"

# ── Baixar arquivos base ──────────────────────────────────────────────────────

section "Baixando arquivos"

curl -fsSL "$BASE_URL/docker-compose.client.yml" -o docker-compose.client.yml
info "docker-compose.client.yml ✓"

curl -fsSL "$BASE_URL/update.sh" -o update.sh
chmod +x update.sh
info "update.sh ✓"

# ── Configurar .env ───────────────────────────────────────────────────────────

section "Configurando variáveis de ambiente"

if [[ -f ".env" ]]; then
  warn ".env já existe — mantendo configuração atual."
else
  DB_PASSWORD_GEN=$(openssl rand -hex 16 2>/dev/null || tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 32)
  SECRET_KEY_GEN=$(openssl rand -hex 32 2>/dev/null || tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 64)

  echo ""
  echo -e "  ${YELLOW}Informe o token de acesso ao registry (GitHub PAT).${RESET}"
  echo -e "  Gere em: ${CYAN}https://github.com/settings/tokens${RESET}  (escopo: read:packages)\n"
  read -rp "  GHCR_TOKEN: " GHCR_TOKEN_INPUT </dev/tty
  echo ""

  cat > .env <<EOF
# ── Banco de dados ────────────────────────────────────────────────────────────
DB_USER=pgwatch
DB_NAME=pgwatch_ai
DB_PASSWORD=${DB_PASSWORD_GEN}

# ── Segurança ─────────────────────────────────────────────────────────────────
SECRET_KEY=${SECRET_KEY_GEN}

# ── Rede ─────────────────────────────────────────────────────────────────────
FRONTEND_PORT=80
IMAGE_TAG=latest

# ── Integrações de IA (configure depois na UI) ────────────────────────────────
ANTHROPIC_API_KEY=

# ── Collector ────────────────────────────────────────────────────────────────
COLLECTOR_INTERVAL_SECONDS=60
ACTIVITY_SAMPLE_INTERVAL_SECONDS=5
ALERT_EVALUATION_INTERVAL_SECONDS=60

# ── Atualização ───────────────────────────────────────────────────────────────
GHCR_TOKEN=${GHCR_TOKEN_INPUT}
GHCR_USER=wislanmoraes
EOF

  info ".env criado ✓  (DB_PASSWORD e SECRET_KEY gerados automaticamente)"
fi

# ── Primeira execução ─────────────────────────────────────────────────────────

section "Subindo containers"

SKIP_SELF_UPDATE=1 bash update.sh

# ── Resumo ────────────────────────────────────────────────────────────────────

section "Instalação concluída"

PORTA=$(grep "^FRONTEND_PORT" .env 2>/dev/null | cut -d= -f2 || echo "80")
IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")

echo ""
echo -e "  ${GREEN}✅ pgwatch-ai instalado com sucesso!${RESET}"
echo ""
echo -e "  Acesse:       ${CYAN}http://${IP}:${PORTA}${RESET}"
echo -e "  Login padrão: ${CYAN}admin / admin${RESET}  ← troque após o primeiro acesso"
echo ""
echo -e "  Para atualizar no futuro:"
echo -e "    ${CYAN}cd ${INSTALL_DIR} && ./update.sh${RESET}"
echo ""
