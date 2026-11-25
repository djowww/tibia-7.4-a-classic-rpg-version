# Documentação — Tibia 7.4 - A classic rpg version

Guias para conhecer o projeto, compilar o servidor e entender seus sistemas.

## Começar

- [Apresentação do projeto](../README.md)
- [Jogar em localhost: servidor, banco e cliente](../local/README.md)
- [Compilação e configuração](building.md)
- [Cliente, launcher, minimapa e site](client-and-web.md)
- [Histórico de mudanças](../CHANGELOG.md)

## Sistemas e regras

- [Market, conquistas, Bestiary, Game Wiki, diário de quests, Loot, baús de exploração, luz e tochas](systems.md)
- [Raridade de equipamentos](item-rarity.md)
- [Fórmulas de dano e defesa](combat-formulas.md)
- [Estrutura e migrações do Market](../data/sql/README-market.md)
- [Compatibilidade documentada com Tibia 7.4](classic-74-compatibility.md)

## Ferramentas

Scripts em [`tools/`](../tools/), executados a partir da raiz do repositório:

- [`generate-game-wiki.py`](../tools/generate-game-wiki.py): gera os dados da Game Wiki do cliente a partir de spawns, monstros, itens e NPCs. Rode depois de mudar qualquer um deles.
- [`generate-minimap.py`](../tools/generate-minimap.py): gera o minimapa completo (`client/data/minimap.otmm`) a partir do mapa do servidor e do `Tibia.dat` do cliente.
- [`generate-minimap-markers.py`](../tools/generate-minimap-markers.py): gera as marcações prontas do minimapa (escadas, lojas, bancos, templos).
- [`build-quest-catalog.py`](../tools/build-quest-catalog.py): gera o catálogo somente leitura do diário de quests.
- [`generate-retired-items.py`](../tools/generate-retired-items.py): gera os ids estáveis dos itens aposentados a partir de `data/items/retired-items.json`.
- [`restore_client_coin_assets.py`](../tools/restore_client_coin_assets.py): restaura a arte das Antigas Coins num cliente 7.72 de referência.
- [`check_lua_lint.py`](../tools/check_lua_lint.py) e [`check_script_lint.py`](../tools/check_script_lint.py): lint de Lua, shell scripts e workflows, comparado com as baselines em `tests/`.
- [`ReleaseSigner/`](../tools/ReleaseSigner/): assina o manifesto das releases do launcher.

## Desenvolvimento

- [Como contribuir](../CONTRIBUTING.md)
- [Testes](../tests/README.md)
- [Infraestrutura](../infra/README.md)
- [Política de segurança](../SECURITY.md)
- [Origem do código e avisos de licença](../NOTICE.md) · [Licença](../LICENSE)

Para cadastro, notícias e download do cliente, acesse o [site oficial](https://tibia74.tech).
