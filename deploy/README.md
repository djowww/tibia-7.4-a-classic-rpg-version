# Arquivos de cliente, site e implantação

Este diretório reúne componentes complementares e ferramentas de implantação. Consulte [cliente, launcher e site](../docs/client-and-web.md) para conhecer os pré-requisitos e componentes externos.

- `client-current/`: snapshot de módulos, layouts e estilos do cliente personalizado; não contém uma distribuição completa do OTClient.
- `launcher/`: fonte do launcher Windows, chave pública de verificação e script de empacotamento. O assinador fica em `../tools/ReleaseSigner/`.
- `site-public/`: páginas PHP, traduções, estilos e manifesto público de downloads. Bibliotecas privadas de autenticação, banco e pagamento precisam ser fornecidas separadamente.
- `nginx/`: configurações e scripts de hardening para uma infraestrutura específica.

Os scripts operacionais contêm pressupostos de ambiente e podem modificar arquivos ou controlar serviços. Revise-os e adapte-os ao seu ambiente antes de executar. Eles não são necessários para compilar o servidor nem são executados automaticamente por um push ao GitHub.
