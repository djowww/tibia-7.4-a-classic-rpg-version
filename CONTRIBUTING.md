# Como contribuir

Tibia 7.4 - A classic rpg version reúne código C++, scripts Lua e componentes complementares do cliente e do portal. Comece pela [documentação](docs/INDEX.md) e pelo [guia de compilação](docs/building.md).

## Relatar um problema

Abra uma [issue](https://github.com/djowww/tibia-7.4-a-classic-rpg-version/issues) com o comportamento esperado, o que aconteceu, a versão ou commit utilizado e os passos para reproduzir. Inclua apenas o trecho de log necessário.

Para vulnerabilidades, use o canal indicado em [SECURITY.md](SECURITY.md).

## Propor uma mudança

1. Crie uma branch a partir da `main` atual.
2. Mantenha o pull request focado em uma mudança e explique o problema que ela resolve.
3. Preserve os avisos de autoria e licença dos arquivos.
4. Atualize a documentação quando mudar uma regra, configuração ou interface.
5. Descreva as verificações realizadas e eventuais limitações.

Use uma instalação isolada para alterações que dependam do mundo, do banco ou de contas. Configurações pessoais, chaves privadas, dumps, logs de jogadores e resultados operacionais ficam fora do Git.

## Onde colocar cada coisa

- Scripts próprios do projeto ficam nas subpastas `custom/` de cada tipo em `data/` (por exemplo `data/talkactions/scripts/custom/` e `data/lib/custom/`), separados dos scripts herdados da base.
- Novos arquivos Lua em `data/lib/custom/` usam camelCase sem prefixo (`explorationChests.lua`, `botDetector.lua`). Os arquivos antigos com prefixo `antigas` mantêm o nome.
- Testes vão na pasta da linguagem em [`tests/`](tests/README.md): `cpp/`, `lua/`, `python/`, `php/` ou `launcher/`.
- Módulos do cliente ficam em `client/modules/`, o site em `site/` e o launcher em `launcher/`.
- Registre mudanças visíveis para jogadores no [CHANGELOG](CHANGELOG.md).

## Verificações

Os workflows em [`.github/workflows/`](.github/workflows/) descrevem as verificações disponíveis de C++, Lua, Python, PHP e launcher. Escolha as que correspondem à mudança.

Para documentação, confira os links relativos e execute `git diff --check`. O [guia dos testes](tests/README.md) mostra como rodar cada suíte. Para alterações no servidor, as opções de testes em [`CMakeLists.txt`](CMakeLists.txt) permitem compilar suítes isoladas; indique no pull request quais foram executadas.

Os módulos em [`client/`](client/) precisam ser integrados a um cliente completo para validação da interface. Os componentes do portal também têm dependências externas, descritas no [guia de cliente e site](docs/client-and-web.md).
