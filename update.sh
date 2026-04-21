#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  pgwatch-ai — Script de atualização para parceiros
#
#  Uso:
#    ./update.sh                          # usa variáveis de ambiente ou .env
#    GHCR_TOKEN=ghp_xxx ./update.sh       # passando token inline
#
#  Ou sempre na versão mais recente, sem baixar nada localmente:
#    curl -fsSL https://raw.githubusercontent.com/wislanmoraes/pgwatchai/main/update.sh | bash
#
#  Variáveis de ambiente:
#    GHCR_TOKEN   Personal Access Token com escopo read:packages
#    GHCR_USER    Usuário GitHub (padrão: wislanmoraes)
#    COMPOSE_FILE Arquivo compose (padrão: docker-compose.client.yml)
#    SKIP_SELF_UPDATE=1  Desativa a auto-atualização deste script
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Cores para output ─────────────────────────────────────────────────────────

GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; RESET="\033[0m"
info()    { echo -e "${GREEN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

# ── Auto-atualização do próprio script ───────────────────────────────────────
# Baixa a versão mais recente de si mesmo do GitHub antes de prosseguir.
# Se executado via pipe (curl | bash), pula esta etapa automaticamente.

SCRIPT_URL="https://raw.githubusercontent.com/wislanmoraes/pgwatchai/main/update.sh"
SELF="$SCRIPT_DIR/update.sh"

if [[ "${SKIP_SELF_UPDATE:-0}" != "1" ]] && [[ -t 0 ]] && command -v curl &>/dev/null; then
  info "Verificando versão do script de atualização..."
  TEMP="$(mktemp)"
  if curl -fsSL "$SCRIPT_URL" -o "$TEMP" 2>/dev/null; then
    if ! cmp -s "$TEMP" "$SELF"; then
      info "Script atualizado. Reiniciando..."
      mv "$TEMP" "$SELF"
      chmod +x "$SELF"
      SKIP_SELF_UPDATE=1 exec bash "$SELF" "$@"
    else
      rm -f "$TEMP"
      info "Script já está na versão mais recente."
    fi
  else
    rm -f "$TEMP"
    warn "Não foi possível verificar atualização do script — continuando com a versão local."
  fi
fi

# ── Auto-atualização do docker-compose.client.yml ────────────────────────────

COMPOSE_URL="https://raw.githubusercontent.com/wislanmoraes/pgwatchai-client/main/docker-compose.client.yml"
if [[ "${SKIP_SELF_UPDATE:-0}" != "1" ]] && command -v curl &>/dev/null; then
  COMPOSE_TMP="$(mktemp)"
  if curl -fsSL "$COMPOSE_URL" -o "$COMPOSE_TMP" 2>/dev/null; then
    TARGET_COMPOSE="$SCRIPT_DIR/${COMPOSE_FILE:-docker-compose.client.yml}"
    if ! cmp -s "$COMPOSE_TMP" "$TARGET_COMPOSE"; then
      info "docker-compose.client.yml atualizado."
      mv "$COMPOSE_TMP" "$TARGET_COMPOSE"
    else
      rm -f "$COMPOSE_TMP"
    fi
  else
    rm -f "$COMPOSE_TMP"
    warn "Não foi possível atualizar docker-compose.client.yml — continuando com a versão local."
  fi
fi

# ── Carrega .env se existir ───────────────────────────────────────────────────

if [[ -f "$SCRIPT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/.env"
  set +a
fi

# ── Configuração ─────────────────────────────────────────────────────────────

GHCR_USER="${GHCR_USER:-wislanmoraes}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.client.yml}"
REGISTRY="ghcr.io"

# ── Verificações ──────────────────────────────────────────────────────────────

if ! command -v docker &>/dev/null; then
  error "Docker não encontrado. Instale o Docker antes de continuar."
  exit 1
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
  error "Arquivo '$COMPOSE_FILE' não encontrado. Execute o script na pasta correta."
  exit 1
fi

# ── Login no registry ─────────────────────────────────────────────────────────

if [[ -n "${GHCR_TOKEN:-}" ]]; then
  info "Fazendo login no $REGISTRY..."
  echo "$GHCR_TOKEN" | docker login "$REGISTRY" -u "$GHCR_USER" --password-stdin
else
  warn "GHCR_TOKEN não definido — assumindo que já está logado no $REGISTRY."
fi

# ── Baixar novas imagens ──────────────────────────────────────────────────────

info "Baixando novas imagens..."
docker compose -f "$COMPOSE_FILE" pull
# WatchShell fica em profile 'tools' e não é puxada pelo pull acima
docker compose -f "$COMPOSE_FILE" --profile tools pull watchshell

# ── Reiniciar serviços ────────────────────────────────────────────────────────

info "Parando containers existentes (mantendo frontend no ar)..."
docker stop pgwatch_backend pgwatch_watchshell pgwatch_db 2>/dev/null || true
docker rm   pgwatch_backend pgwatch_watchshell pgwatch_db 2>/dev/null || true

info "Subindo banco e backend com as novas imagens..."
# depends_on: timescaledb: condition: service_healthy garante a ordem correta
docker compose -f "$COMPOSE_FILE" up -d timescaledb backend

info "Aguardando backend ficar saudável..."
for i in $(seq 1 30); do
  sleep 3
  if docker exec pgwatch_backend curl -sf http://localhost:8000/health >/dev/null 2>&1; then
    info "Backend saudável."
    break
  fi
  echo "  aguardando... ($i/30)"
done

info "Atualizando frontend..."
docker stop pgwatch_frontend 2>/dev/null || true
docker rm   pgwatch_frontend 2>/dev/null || true
docker compose -f "$COMPOSE_FILE" up -d frontend

info "Subindo demais serviços..."
# --no-recreate: não recria containers já em execução (ex: pgwatch_updater que está rodando este script)
docker compose -f "$COMPOSE_FILE" up -d --no-recreate --remove-orphans

# ── Limpeza de imagens antigas ────────────────────────────────────────────────

info "Removendo imagens não utilizadas para liberar espaço..."
docker image prune -f

# ── Verificação final ─────────────────────────────────────────────────────────

echo ""
info "Status dos containers:"
docker compose -f "$COMPOSE_FILE" ps

echo ""
info "✅ Atualização concluída com sucesso!"
