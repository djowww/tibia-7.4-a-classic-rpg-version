# Infraestrutura

Configurações e scripts de implantação de uma infraestrutura específica. Não são necessários para compilar o servidor nem para jogar em localhost, e nenhum deles roda sozinho num push ao GitHub.

- `nginx/`: configurações de cabeçalhos de segurança, IP real atrás da Cloudflare e scripts de hardening.

Os scripts contêm pressupostos de ambiente e podem modificar arquivos ou controlar serviços. Revise e adapte cada um antes de executar.

Os outros componentes ficam na raiz do repositório:

- [`client/`](../client/): módulos, layouts e estilos do cliente personalizado (não é uma distribuição completa do OTClient).
- [`launcher/`](../launcher/): código do launcher Windows, chave pública de verificação e script de empacotamento. O assinador fica em [`tools/ReleaseSigner/`](../tools/ReleaseSigner/).
- [`site/`](../site/): páginas PHP, traduções, estilos e manifesto público de downloads. As bibliotecas privadas de autenticação, banco e pagamento são fornecidas à parte.

Consulte [cliente, launcher e site](../docs/client-and-web.md).
