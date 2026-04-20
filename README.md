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

O script se auto-atualiza antes de executar — não é necessário baixar uma nova versão manualmente.

## Suporte

Em caso de dúvidas, entre em contato com o suporte técnico.
