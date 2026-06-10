# pgwatch-ai — Instalação do Cliente

Monitoramento de PostgreSQL com inteligência artificial.

## Pré-requisitos

- Docker 24+ com Docker Compose plugin
- Porta **80** liberada para entrada
- Acesso à internet (saída 443) para pull das imagens
- Token de acesso fornecido pelo suporte (`GHCR_TOKEN`)

## Instalação

Execute em qualquer terminal com Docker instalado:

```bash
curl -fsSL https://raw.githubusercontent.com/wislanmoraes/pgwatchai-client/main/install.sh | bash
```

O instalador irá:
1. Verificar os pré-requisitos
2. Criar o diretório `~/pgwatchai`
3. Solicitar o token de acesso (`GHCR_TOKEN`)
4. Gerar senha do banco e chave de segurança automaticamente
5. Subir todos os containers

Ao final, a URL de acesso e o login padrão serão exibidos.

## Atualização

Quando uma nova versão estiver disponível, um badge verde aparecerá na interface.
Clique em **Atualizar agora** ou execute no servidor:

```bash
cd ~/pgwatchai && ./update.sh
```

A cada execução, o script realiza automaticamente:
1. **Auto-atualização do próprio script** — baixa a versão mais recente do `update.sh`
2. **Atualização do `docker-compose.client.yml`** — garante que novos serviços e configurações sejam aplicados
3. **Pull e restart das imagens Docker** — atualiza o backend, frontend e demais containers

Não é necessário baixar ou editar nenhum arquivo manualmente.

## Reinstalação limpa

Em atualizações que exijam apagar os dados históricos (ex: mudança de versão do PostgreSQL),
execute o instalador novamente — ele detectará a instalação existente e oferecerá a opção de reinstalar:

```bash
curl -fsSL https://raw.githubusercontent.com/wislanmoraes/pgwatchai-client/main/install.sh | bash
```

Escolha a opção **[2] Reinstalação limpa** no menu. Os dados de monitoramento serão apagados,
mas o arquivo `.env` (token, senhas, porta) é preservado — não é necessário reconfigurar.

Para ambientes automatizados (sem prompt interativo):

```bash
PGWATCH_FRESH=1 curl -fsSL https://raw.githubusercontent.com/wislanmoraes/pgwatchai-client/main/install.sh | bash
```

## Suporte

Em caso de dúvidas, entre em contato com o suporte técnico.
