# Sistemas do Antigas

Este guia apresenta o comportamento dos sistemas customizados de Tibia 7.4 - A classic rpg version (anteriormente Antigas). As interfaces dependem dos módulos correspondentes do cliente oficial e das extensões de comunicação do servidor.

## Market

O Market permite criar ofertas de compra e venda em **Gold** ou **Antigas Coins**. Uma oferta reserva os itens ou a moeda necessários e pode ser negociada parcialmente. Cancelamentos e negociações geram entregas pendentes, recolhidas pelo personagem na interface do Market.

O histórico registra compras, vendas e cancelamentos junto às operações do sistema. A coleta parcial preserva o saldo pendente; a coleta completa registra a entrega como recolhida. Gold é enviado ao banco do personagem; itens e Antigas Coins são entregues ao depot da sua cidade.

O catálogo oferece filtro de itens próprios e os melhores preços das ofertas ativas por moeda. Esses valores representam as ofertas disponíveis, sem misturar Gold e Antigas Coins nem garantir que uma negociação será concluída naquele preço.

As ofertas representam tipo e quantidade de item. Equipamentos raros ou refinados são recusados, pois carregam atributos individuais que esse formato não preserva. Containers, fluidos e itens com identificadores especiais também têm restrições. Wands e rods de combate são bloqueadas para novas ofertas; a fishing rod permanece disponível.

O banco precisa das migrações `market.sql`, `market-v2.sql` e `market-v3.sql`, nessa ordem, para uma instalação nova do Market. Consulte a [documentação SQL](../data/sql/README-market.md) para os detalhes da estrutura.

Referências: [`market.lua`](../data/creaturescripts/scripts/custom/market.lua) e [`economy.lua`](../data/lib/custom/economy.lua).

## Achievements

As conquistas acompanham objetivos do personagem e guardam progresso e recompensas em storages persistentes. O servidor calcula os contadores, os marcos e os prêmios; o cliente exibe o progresso e solicita o resgate.

O painel destaca metas próximas e recompensas pendentes. Ao atingir uma meta, o direito ao prêmio fica registrado antes da tentativa de entrega. Se faltar capacidade ou espaço, a recompensa permanece pendente para resgate posterior. Repetir o pedido não entrega novamente um prêmio já recebido.

Referências: [`antigasAchievements.lua`](../data/lib/custom/antigasAchievements.lua) e [`achievements.lua`](../data/creaturescripts/scripts/custom/achievements.lua).

## Bestiary

O Bestiary mantém contadores de abates por monstro e personagem. Os dados são persistidos no servidor e enviados ao cliente para apresentação do catálogo e do progresso. Monstros invocados por jogadores não contam para esse progresso.

Cada Bestiary concluído concede um bônus permanente de **0,2% de experiência**. O servidor controla os contadores e o total de conclusões.

No cliente, o Bestiary é uma aba da **Game Wiki** (botão Wiki do inventário), ao lado da Itempedia e do Hunting Guide. Os dados dessas abas são gerados dos arquivos do servidor por [`generate-game-wiki.py`](../tools/generate-game-wiki.py): locais vêm de `spawns.xml`, loot dos monstros, atributos de `items.srv` e compra e venda dos NPCs. Rode o script depois de mudar spawns, monstros, itens ou NPCs.

Referências: [`antigasBestiary.lua`](../data/lib/custom/antigasBestiary.lua) e [`bestiary.lua`](../data/creaturescripts/scripts/custom/bestiary.lua).

## Diário de quests

O diário acompanha as descobertas do personagem. Listas, busca, filtros e detalhes incluem apenas quests conhecidas e etapas aceitas ou concluídas; o servidor filtra as respostas antes de enviá-las ao cliente.

O catálogo interpreta os estados existentes das quests. Uma missão sem sinal de início pode aparecer somente quando sua conclusão é registrada. As notas apresentam o progresso conhecido, e recompensas específicas são mostradas apenas quando os registros permitem identificar o item recebido.

Esse diário organiza a informação para o jogador sem substituir os scripts originais de NPCs, missões e recompensas.

Referências: [`questJournal.lua`](../data/lib/custom/questJournal.lua), [`questCatalog.lua`](../data/lib/custom/questCatalog.lua) e [`questlog.lua`](../data/creaturescripts/scripts/custom/questlog.lua).

## Raridade de equipamentos

Equipamentos elegíveis do loot de monstros podem receber raridade e atributos adicionais. Há cinco tiers: **incomum, raro, épico, lendário e mítico**. A raridade pertence ao exemplar do item e acompanha sua persistência e transformações.

O cliente utiliza bordas, cores e tooltips para apresentar os atributos. A identificação visual aparece no inventário, nos containers abertos e nos itens no chão. As integrações de comércio protegem itens com atributos individuais contra negociações que perderiam esses dados.

Consulte [raridade de equipamentos](item-rarity.md) para conhecer os pesos, bônus, itens elegíveis e detalhes da persistência.

## Loot

O canal **Loot** abre ao entrar no jogo e pode ser reaberto na lista de canais. Cada morte gera uma mensagem para o dono do loot e os membros da party naquele momento. Os nomes dos itens usam a raridade de cada exemplar, permitindo cores diferentes para itens do mesmo tipo.

Drops com raridade também geram um efeito e texto animado para os destinatários com o corpo visível. A cor do aviso corresponde à maior raridade encontrada.

Referências: [`loot.cpp`](../src/loot.cpp) e [`loot.lua`](../data/chatchannels/scripts/custom/loot.lua).

## Baús de exploração

Cada região tem um baú escondido: Thais, Carlin, Kazordoon, Ab'Dendriel, Edron, Darashia, Venore, Ankrahmun, Rookgaard e Port Hope. A cada início do servidor o baú de cada região é sorteado entre alguns esconderijos possíveis, em cantos fora do caminho e longe de casas e áreas protegidas.

Ao abrir um baú, o jogador escolhe um de três prêmios na janela **Exploration**:

- **Ouro:** 0,4% da experiência total do personagem.
- **Mana:** +0,2% de mana máxima e regeneração extra de mana.
- **Vida:** +0,3% de vida máxima e regeneração extra de vida.

Cada baú só pode ser pego uma vez por personagem, e os bônus de atributo continuam valendo depois de sair e entrar de novo. A janela mostra quantas regiões o personagem já explorou. A equipe vê a lista dos baús do boot atual com o comando `/chests`.

Referências: [`explorationChests.lua`](../data/lib/custom/explorationChests.lua), [`exploration_chest.lua`](../data/actions/scripts/custom/exploration_chest.lua) e o módulo do cliente [`game_exploration`](../client/modules/game_exploration/).

## Luz e tochas

A luz do jogo fica sempre ligada no cliente, como no 7.4: a opção de desligar as luzes e o ajuste de luz ambiente foram travados, então lugares escuros continuam escuros. Para compensar, as tochas acesas duram o dobro do tempo original.

O terminal Lua do cliente (Ctrl+T) só abre para contas da equipe.

Referências: [`options.lua`](../client/modules/client_options/options.lua), [`terminal.lua`](../client/modules/client_terminal/terminal.lua) e os tempos das tochas em `data/items/items.srv`.

## Janela de Skills

As barras de progresso das skills usam um trilho escuro discreto, sem contorno preto, e ficam vazias em 0%. A janela também mostra o tempo restante de comida na linha Food.

Referências: [`skills.otui`](../client/modules/game_skills/skills.otui) e [`skills.lua`](../client/modules/game_skills/skills.lua).

## Detecção de bots

O servidor acompanha padrões de jogo automatizado e avisa a equipe quando um personagem parece usar bot. Nenhuma punição é automática: a decisão fica com a equipe. Os critérios não são documentados publicamente.

O launcher oficial participa com o **Guardian**. Antes de abrir o jogo ele confere os arquivos do cliente com a lista assinada da versão (`client.files.json`), procura programas de bot conhecidos e pede ao servidor um token de sessão, que o cliente apresenta ao entrar e que o launcher renova a cada minuto. Quem entra sem o launcher, fecha o launcher durante o jogo ou joga com arquivos alterados soma pontos no mesmo alerta para a equipe. O launcher roda no computador do jogador e pode ser burlado, por isso o servidor nunca confia só nele; `requireLauncher` em [`guardian.lua`](../data/lib/custom/guardian.lua) permite recusar quem entra sem o launcher.

## Combate e conteúdo legado

As [fórmulas de combate](combat-formulas.md) descrevem os cálculos do núcleo e seus pontos de integração. Scripts de magias e definições de monstros podem estabelecer valores específicos.

Os sistemas Tusker (NPCs, tarefas e comando `!tasks`), bounty hunter (`!hunt`), coleta automática customizada de frascos vazios (`!vial`) e chance legada de dano crítico foram retirados. O uso normal de frascos e os diálogos dos NPCs para comprar, usar ou vender vials permanecem disponíveis.

[`src/tasks.cpp`](../src/tasks.cpp) implementa a infraestrutura interna de filas do servidor e não depende do sistema de tarefas dos NPCs.
