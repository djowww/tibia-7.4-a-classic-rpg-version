# Scripts não utilizados

Esta pasta guarda scripts Lua que vieram da base do servidor, mas que **não são
carregados** por esta versão. Nenhum deles está registrado nos arquivos XML de
`data/` (`actions.xml`, `movements.xml`, `spells.xml` etc.), e o núcleo só
carrega os scripts listados nesses arquivos. Por isso, mantê-los aqui não muda
nada no jogo.

Eles foram separados para deixar `data/` apenas com o que o servidor realmente
usa, sem perder o código para quem quiser estudá-lo ou reaproveitá-lo. A
maioria é de sistemas que não existiam no Tibia 7.4 (premium por item, bônus
de experiência, offline training, exercise weapons, potions), duplicatas de
scripts ativos ou magias de monstros que nenhum monstro usa.

## Estrutura

Os arquivos mantêm o mesmo caminho que tinham em `data/`. Por exemplo,
`unused-scripts/data/actions/scripts/others/dice.lua` estava em
`data/actions/scripts/others/dice.lua`.

| Pasta | Conteúdo |
| --- | --- |
| `data/actions/scripts/others/` | Itens de premium (`premium7/15/30.lua`), bônus de experiência (`exp.lua`), bless por item (`bless.lua`, `checkBless.lua`), remoção de skull (`frag_remove.lua`), conversor de gold (`goldconverter.lua`), scrolls de templo e de casa, potions (`newpots.lua`), estátuas de offline training, tickets de pontos (`points.lua`), liberações de quest por item (`avartar.lua`, `djinn_blue.lua`, `djinn_green.lua`, `postman.lua`, `spectral_stone.lua`) e variantes antigas de ferramentas (`rope2.lua`, `shovel2.lua`, `skinning-knife.lua`, `snake_destroyer.lua`), além de `dice.lua`, `panda_teddy.lua` e `furniture_parcels.lua`. |
| `data/creaturescripts/scripts/` | Arena de monstros (`arena/arena.lua`) e offline training no login (`others/offlinetraining.lua`). |
| `data/movements/scripts/` | Entrada e saída da arena (`arena/`) e uma lixeira duplicada (`others/dustbin2.lua`). |
| `data/spells/scripts/monster/` | Magias de monstros sem registro em `spells.xml`: hastes e paralyzes específicos de cada monstro, magias de evento (`easterbomb.lua`) e outras que os monstros desta versão não usam. |
| `data/weapons/scripts/` | Exercise weapons (`exercise_training_*.lua`), um sistema de versões muito posteriores. |

## Reativar um script

1. Mova o arquivo de volta para o mesmo caminho dentro de `data/`.
2. Registre-o no XML correspondente. Exemplo para uma action:

   ```xml
   <action itemid="ID_DO_ITEM" script="others/dice.lua" />
   ```

3. Confira se as funções Lua que ele chama existem neste núcleo. Parte destes
   scripts foi escrita para outras bases e usa funções antigas ou ausentes.
4. Reinicie o servidor e verifique o console para erros de carregamento.

Esses scripts não foram revisados nem testados nesta versão. Revise cada um
antes de usá-los em um servidor aberto: alguns entregam premium, experiência
ou remoção de skull sem nenhum custo.
