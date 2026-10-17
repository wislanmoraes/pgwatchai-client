#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  pgwho — Script de atualização para parceiros
#
#  Uso:
#    ./update.sh                          # usa variáveis de ambiente ou .env
#    GHCR_TOKEN=ghp_xxx ./update.sh       # passando token inline
#
#  Ou sempre na versão mais recente, sem baixar nada localmente:
#    curl -fsSL https://raw.githubusercontent.com/wislanmoraes/pgwho-client/main/update.sh | bash
#
#  Variáveis de ambiente:
#    GHCR_TOKEN       Personal Access Token com escopo read:packages
#    GHCR_USER        Usuário GitHub (padrão: wislanmoraes)
#    COMPOSE_FILE     Arquivo compose (padrão: docker-compose.client.yml)
#    HOST_DEPLOY_DIR  Caminho REAL no host do diretório de deploy (setado
#                      automaticamente pelo compose via ${PWD} na criação do
#                      updater) — necessário pra ele recriar a si mesmo.
#    SKIP_SELF_UPDATE=1  Desativa a auto-atualização deste script
#
#  Nota pra instalações de ANTES desta variável existir: a primeira
#  atualização depois de adotar isso ainda vai pedir um passo manual único
#  (o updater atual em execução não tem HOST_DEPLOY_DIR) — depois disso,
#  nunca mais precisa de intervenção manual:
#    docker compose -f docker-compose.client.yml up -d --force-recreate updater
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# DEPLOY_DIR (setado pelo sidecar `updater`, ver updater/main.py
# _fresh_update_script) tem prioridade sobre BASH_SOURCE: o sidecar busca
# uma cópia FRESCA deste script em /tmp antes de cada execução (contorna o
# bind mount :ro de update.sh e evita self-modificação de um script em
# execução — ver Issue #74), então ${BASH_SOURCE[0]} apontaria pra /tmp, não
# pra onde .env/docker-compose.client.yml realmente estão.
SCRIPT_DIR="${DEPLOY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# ── Cores para output ─────────────────────────────────────────────────────────

GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; RESET="\033[0m"
info()    { echo -e "${GREEN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

# ── Auto-atualização do próprio script ───────────────────────────────────────
# Baixa a versão mais recente de si mesmo do GitHub antes de prosseguir.
# Se executado via pipe (curl | bash), pula esta etapa automaticamente.

SCRIPT_URL="https://raw.githubusercontent.com/wislanmoraes/pgwho-client/main/update.sh"
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
# Roda sempre (independente de SKIP_SELF_UPDATE) para garantir que novos
# serviços (ex: updater sidecar) sejam adicionados ao compose do cliente.

COMPOSE_URL="https://raw.githubusercontent.com/wislanmoraes/pgwho-client/main/docker-compose.client.yml"
if command -v curl &>/dev/null; then
  COMPOSE_TMP="$(mktemp)"
  if curl -fsSL "$COMPOSE_URL" -o "$COMPOSE_TMP" 2>/dev/null; then
    TARGET_COMPOSE="$SCRIPT_DIR/${COMPOSE_FILE:-docker-compose.client.yml}"
    if ! cmp -s "$COMPOSE_TMP" "$TARGET_COMPOSE"; then
      info "docker-compose.client.yml atualizado."
      # Achado ao vivo num cliente: este arquivo é montado no sidecar
      # `updater` como bind mount de ARQUIVO ÚNICO (ver docker-compose.
      # client.yml, serviço updater — precisa ser gravável, ao contrário de
      # .env/update.sh que são :ro). `mv` faz um rename() atômico, que TROCA
      # o inode do destino — o kernel recusa isso quando o caminho tem algo
      # montado nele (exatamente o que um bind mount de arquivo é) e devolve
      # EBUSY ("Resource busy"), abortando a atualização logo depois de
      # baixar o compose novo, antes até do `docker compose pull`. `cat` (ou
      # `cp` sem --remove-destination) escreve NO MESMO inode em vez de
      # trocá-lo — compatível com esse tipo de bind mount.
      cat "$COMPOSE_TMP" > "$TARGET_COMPOSE"
      rm -f "$COMPOSE_TMP"
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

# ── Preservação automática de volume (migração pgwatchai -> pgwho) ────────────
if [[ -z "${DATA_VOLUME_NAME:-}" ]] && docker volume inspect pgwatchai_timescaledb_data >/dev/null 2>&1; then
  export DATA_VOLUME_NAME="pgwatchai_timescaledb_data"
  export DB_USER="${DB_USER:-pgwatch}"
  export DB_NAME="${DB_NAME:-pgwatch_ai}"
  if [[ -w "$SCRIPT_DIR/.env" ]]; then
    if ! grep -q '^DATA_VOLUME_NAME=' "$SCRIPT_DIR/.env"; then
      echo "DATA_VOLUME_NAME=pgwatchai_timescaledb_data" >> "$SCRIPT_DIR/.env"
    fi
    if ! grep -q '^DB_USER=' "$SCRIPT_DIR/.env"; then
      echo "DB_USER=$DB_USER" >> "$SCRIPT_DIR/.env"
    fi
    if ! grep -q '^DB_NAME=' "$SCRIPT_DIR/.env"; then
      echo "DB_NAME=$DB_NAME" >> "$SCRIPT_DIR/.env"
    fi
    info "Volume legado (pgwatchai_timescaledb_data) detectado e preservado no .env."
  elif [[ -w "$SCRIPT_DIR/$COMPOSE_FILE" ]]; then
    sed -i 's/pgwho_timescaledb_data/pgwatchai_timescaledb_data/g' "$SCRIPT_DIR/$COMPOSE_FILE" 2>/dev/null || true
    info "Volume legado (pgwatchai_timescaledb_data) detectado e preservado no compose."
  fi
fi

# ── Baixar novas imagens ──────────────────────────────────────────────────────

info "Baixando novas imagens..."
docker compose -f "$COMPOSE_FILE" pull
# WatchShell fica em profile 'tools' e não é puxada pelo pull acima
docker compose -f "$COMPOSE_FILE" --profile tools pull watchshell

# ── Reiniciar serviços ────────────────────────────────────────────────────────

info "Parando containers existentes (mantendo frontend no ar)..."
docker stop pgwho_backend pgwho_watchshell pgwho_db pgwatch_backend pgwatch_watchshell pgwatch_db 2>/dev/null || true
docker rm   pgwho_backend pgwho_watchshell pgwho_db pgwatch_backend pgwatch_watchshell pgwatch_db 2>/dev/null || true

info "Subindo banco e backend com as novas imagens..."
# depends_on: timescaledb: condition: service_healthy garante a ordem correta
docker compose -f "$COMPOSE_FILE" up -d timescaledb backend

info "Aguardando backend ficar saudável..."
for i in $(seq 1 30); do
  sleep 3
  if docker exec pgwho_backend curl -sf http://localhost:8000/health >/dev/null 2>&1; then
    info "Backend saudável."
    break
  fi
  echo "  aguardando... ($i/30)"
done

info "Atualizando frontend..."
docker stop pgwho_frontend pgwatch_frontend 2>/dev/null || true
docker rm   pgwho_frontend pgwatch_frontend 2>/dev/null || true
docker compose -f "$COMPOSE_FILE" up -d frontend

info "Subindo demais serviços..."
# --no-recreate: não recria containers já em execução (ex: pgwho_updater que está rodando este script)
docker compose -f "$COMPOSE_FILE" up -d --no-recreate --remove-orphans

# ── Auto-recriação do updater ─────────────────────────────────────────────────
# O updater nunca recria a si mesmo acima (--no-recreate, de propósito: é este
# script rodando dentro dele). Isso significa que mudanças no próprio serviço
# `updater` do compose (nova imagem, novos mounts, novo healthcheck) nunca se
# aplicam sozinhas — historicamente exigiam um `docker compose up -d
# --force-recreate updater` manual depois de toda atualização normal.
#
# Se executado diretamente no terminal do host (! -f /.dockerenv), podemos
# recriar o updater diretamente. Se executado de dentro do sidecar updater,
# delegamos a um container auxiliar descartável usando HOST_DEPLOY_DIR.
if [[ ! -f /.dockerenv ]]; then
  info "Recriando serviço updater no host..."
  docker rm -f pgwatch_updater 2>/dev/null || true
  docker compose -f "$COMPOSE_FILE" up -d --force-recreate --no-deps updater
elif [[ -z "${HOST_DEPLOY_DIR:-}" ]]; then
  warn "HOST_DEPLOY_DIR não definido — pulando auto-recriação do updater."
  warn "Instalações antigas (de antes desta variável existir) precisam de:"
  warn "  docker compose -f $COMPOSE_FILE up -d --force-recreate updater"
else
  info "Agendando recriação do updater (em container auxiliar separado)..."
  # sleep 2 dá tempo do `docker run -d` retornar e este script terminar
  # (state.push_done() no updater dispara e a UI já reporta sucesso) antes
  # do updater antigo ser efetivamente derrubado.
  docker run --rm -d \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$HOST_DEPLOY_DIR:$HOST_DEPLOY_DIR" \
    -w "$HOST_DEPLOY_DIR" \
    docker:27-cli \
    sh -c "sleep 2 && docker rm -f pgwatch_updater 2>/dev/null || true; docker compose -f '$COMPOSE_FILE' up -d --force-recreate --no-deps updater" \
    >/dev/null
fi

# ── Limpeza de imagens antigas ────────────────────────────────────────────────

info "Removendo imagens não utilizadas para liberar espaço..."
docker image prune -f

# ── Verificação final ─────────────────────────────────────────────────────────

echo ""
info "Status dos containers:"
docker compose -f "$COMPOSE_FILE" ps

echo ""
info "✅ Atualização concluída com sucesso!"
