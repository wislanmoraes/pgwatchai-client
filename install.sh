#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  pgwatch-ai — Instalação inicial
#
#  Uso (em qualquer VM com Docker):
#    curl -fsSL https://raw.githubusercontent.com/wislanmoraes/pgwatchai/main/install.sh | bash
#
#  O script:
#    1. Verifica pré-requisitos (Docker, Docker Compose, curl)
#    2. Cria o diretório ~/pgwatchai
#    3. Baixa docker-compose.client.yml e update.sh
#    4. Coleta configurações interativamente (com padrões inteligentes)
#    5. Faz login no GHCR e sobe os containers
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

BASE_URL="https://raw.githubusercontent.com/wislanmoraes/pgwatchai-client/main"
INSTALL_DIR="${PGWATCH_DIR:-$HOME/pgwatchai}"

GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; CYAN="\033[0;36m"; DIM="\033[2m"; RESET="\033[0m"
info()    { echo -e "${GREEN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
section() { echo -e "\n${CYAN}━━━ $* ${RESET}"; }
default() { echo -e "  ${DIM}↳ $*${RESET}"; }

# Verifica se uma porta já está em uso (Docker ou sistema).
# Retorna 0 = livre, 1 = em uso.
# Imprime na stdout quem está usando quando em uso.
port_in_use() {
  local port="$1"

  # ── Docker containers ───────────────────────────────────────────────────────
  local docker_hit
  docker_hit=$(docker ps --format '{{.Names}}\t{{.Ports}}' 2>/dev/null \
    | grep -E "(^|[^0-9])${port}->" || true)
  if [[ -n "$docker_hit" ]]; then
    local container
    container=$(echo "$docker_hit" | awk '{print $1}')
    echo -e "  ${RED}✗ Porta ${port} já usada pelo container Docker: ${YELLOW}${container}${RESET}"
    return 1
  fi

  # ── Sistema operacional (ss ou netstat como fallback) ───────────────────────
  local sys_hit=""
  if command -v ss &>/dev/null; then
    sys_hit=$(ss -tlnp 2>/dev/null | grep -E ":${port}\b" | awk '{print $NF}' || true)
  elif command -v netstat &>/dev/null; then
    sys_hit=$(netstat -tlnp 2>/dev/null | grep -E ":${port}\b" | awk '{print $NF}' || true)
  fi
  if [[ -n "$sys_hit" ]]; then
    echo -e "  ${RED}✗ Porta ${port} já usada pelo processo: ${YELLOW}${sys_hit}${RESET}"
    return 1
  fi

  return 0
}

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

for cmd in docker curl openssl; do
  if ! command -v "$cmd" &>/dev/null; then
    error "$cmd não encontrado. Instale antes de continuar."
    exit 1
  fi
  info "$cmd ✓"
done

if ! docker compose version &>/dev/null; then
  error "Docker Compose plugin não encontrado. Execute: apt install docker-compose-plugin"
  exit 1
fi
info "docker compose ✓"

if ! docker info &>/dev/null; then
  error "Docker daemon não está rodando ou seu usuário não tem permissão."
  error "Execute: systemctl start docker  (ou adicione seu usuário ao grupo docker)"
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
  warn ".env já existe — pulando criação. Edite manualmente se necessário."
else
  # Valores gerados automaticamente
  DB_PASSWORD_GEN=$(openssl rand -hex 16)
  SECRET_KEY_GEN=$(openssl rand -hex 32)

  echo ""
  echo -e "  Pressione ${CYAN}Enter${RESET} para aceitar o valor padrão indicado em ${CYAN}[colchetes]${RESET}."
  echo ""

  # ── GHCR Token (obrigatório) ──────────────────────────────────────────────
  echo -e "  ${YELLOW}[OBRIGATÓRIO]${RESET} GitHub Container Registry"
  echo -e "  Crie um token em: ${CYAN}https://github.com/settings/tokens${RESET}"
  echo -e "  Escopo necessário: ${CYAN}read:packages${RESET}"
  echo ""
  while true; do
    read -rp "  GHCR_TOKEN: " GHCR_TOKEN_INPUT </dev/tty
    [[ -n "$GHCR_TOKEN_INPUT" ]] && break
    echo -e "  ${RED}Token obrigatório.${RESET} Sem ele não é possível baixar as imagens."
  done
  echo ""

  # ── Porta do painel (com verificação de conflito) ────────────────────────
  echo -e "  ${CYAN}[OPCIONAL]${RESET} Porta do painel web"
  default "padrão: 80 — verificamos se já está em uso antes de continuar"
  while true; do
    read -rp "  FRONTEND_PORT [80]: " FRONTEND_PORT_INPUT </dev/tty
    FRONTEND_PORT="${FRONTEND_PORT_INPUT:-80}"
    if port_in_use "$FRONTEND_PORT"; then
      info "Porta ${FRONTEND_PORT} disponível ✓"
      break
    fi
    echo -e "  ${YELLOW}Escolha outra porta ou resolva o conflito antes de continuar.${RESET}"
  done
  echo ""

  # ── Chave de IA (opcional) ────────────────────────────────────────────────
  echo -e "  ${CYAN}[OPCIONAL]${RESET} Chave de API de IA (Anthropic, OpenAI ou Google)"
  default "pode ser configurada depois na interface"
  read -rp "  ANTHROPIC_API_KEY [não configurado]: " ANTHROPIC_API_KEY_INPUT </dev/tty
  ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY_INPUT:-}"
  echo ""

  # ── Resumo antes de gravar ────────────────────────────────────────────────
  echo -e "  ${DIM}─────────────────────────────────────────${RESET}"
  echo -e "  ${DIM}FRONTEND_PORT   = ${FRONTEND_PORT}${RESET}"
  echo -e "  ${DIM}DB_PASSWORD     = (gerado automaticamente)${RESET}"
  echo -e "  ${DIM}SECRET_KEY      = (gerado automaticamente)${RESET}"
  echo -e "  ${DIM}ANTHROPIC_API_KEY = ${ANTHROPIC_API_KEY:-não configurado}${RESET}"
  echo -e "  ${DIM}GHCR_TOKEN      = ${GHCR_TOKEN_INPUT:0:8}…(oculto)${RESET}"
  echo -e "  ${DIM}─────────────────────────────────────────${RESET}"
  echo ""

  cat > .env <<EOF
# ── Banco de dados ────────────────────────────────────────────────────────────
DB_USER=pgwatch
DB_NAME=pgwatch_ai
DB_PASSWORD=${DB_PASSWORD_GEN}

# ── Segurança ─────────────────────────────────────────────────────────────────
SECRET_KEY=${SECRET_KEY_GEN}

# ── Rede ──────────────────────────────────────────────────────────────────────
FRONTEND_PORT=${FRONTEND_PORT}
IMAGE_TAG=latest

# ── Integrações de IA (configure depois na UI se preferir) ────────────────────
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}

# ── Collector ─────────────────────────────────────────────────────────────────
COLLECTOR_INTERVAL_SECONDS=60
ACTIVITY_SAMPLE_INTERVAL_SECONDS=5
ALERT_EVALUATION_INTERVAL_SECONDS=60

# ── Atualização ───────────────────────────────────────────────────────────────
GHCR_TOKEN=${GHCR_TOKEN_INPUT}
GHCR_USER=wislanmoraes
EOF

  info ".env criado ✓"
fi

# ── Primeira execução ─────────────────────────────────────────────────────────

section "Subindo containers"

SKIP_SELF_UPDATE=1 bash update.sh

# ── Resumo ────────────────────────────────────────────────────────────────────

section "Instalação concluída"

PORTA=$(grep -E '^FRONTEND_PORT=' .env 2>/dev/null | cut -d= -f2 || echo "80")
IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "  ${GREEN}✅ pgwatch-ai instalado com sucesso!${RESET}"
echo ""
echo -e "  Acesse:       ${CYAN}http://${IP}:${PORTA}${RESET}"
echo -e "  Login padrão: ${CYAN}admin / admin${RESET}  ← troque a senha após o primeiro acesso"
echo ""
echo -e "  Arquivos em:  ${CYAN}${INSTALL_DIR}${RESET}"
echo ""
echo -e "  Para atualizar no futuro:"
echo -e "    ${CYAN}cd ${INSTALL_DIR} && ./update.sh${RESET}"
echo ""
