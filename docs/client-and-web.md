# Cliente, launcher e site

O projeto se chama Tibia 7.4 - A classic rpg version, anteriormente Antigas. O cliente distribuído e os serviços existentes ainda podem apresentar o nome anterior e utilizam extensões próprias. A compatibilidade exige os módulos, opcodes e chave pública esperados pelo servidor.

## Snapshot do cliente

[client/](../client/) contém arquivos selecionados de uma distribuição personalizada baseada em OTClient: inicialização, módulos Lua, layouts OTUI e estilos. Não inclui o código C++ completo do OTClient, seu executável nem todos os assets necessários para montar o cliente do zero.

O snapshot versionado agora usa o perfil local, com login em `127.0.0.1:17173`. O iniciador **Tibia74-Local.exe** (código em [local/launcher](../local/launcher/Tibia74Local.cs)) obtém o cliente completo da release e copia para ele a chave pública gerada pelo servidor local. O placeholder RSA do snapshot não é uma chave utilizável antes dessa preparação. Consulte o [guia local](../local/README.md). Para hospedar outro ambiente, ajuste os endpoints e a chave pública correspondente. O número de release do cliente é independente da versão de protocolo.

Copie também `client.version` ao integrar o snapshot: o launcher consulta esse marcador antes de `APP_VERSION` em `init.lua`. O empacotador atualiza ambos e as instruções com a versão solicitada; cada execução exige uma pasta de saída nova.

## Minimapa completo

[client/data/minimap.otmm](../client/data/minimap.otmm) é o minimapa do mundo inteiro, com os 16 andares já revelados. O cliente carrega `data/minimap.otmm` antes do arquivo de minimapa do próprio jogador, então todo personagem começa com o mapa aberto. As marcações feitas pelo jogador continuam salvas à parte.

O arquivo é gerado a partir do mapa do servidor e do `Tibia.dat` do cliente 7.72, com as mesmas cores, bloqueios e velocidades que o cliente gravaria ao explorar cada tile:

```sh
python3 tools/generate-minimap.py --dat caminho/para/data/things/772/Tibia.dat --out client/data/minimap.otmm
```

Gere de novo sempre que `data/world/map.otbm` mudar. O pacote local inclui o arquivo automaticamente; ao montar a distribuição de produção, copie-o para a pasta `data/` do cliente.

## Marcações prontas no minimapa

[client/data/minimap-markers.txt](../client/data/minimap-markers.txt) traz as marcações que todo jogador já vê no minimapa, uma por linha no formato `x,y,z,ícone,descrição`:

| Ícone | O que marca |
| --- | --- |
| Seta para cima | Escadas, rampas, escadas de mão e pontos de corda que sobem |
| Seta para baixo | Buracos, escadas e grades que descem |
| Bolsa | NPCs que negociam runas, wands ou blank runes |
| Espada | NPCs que negociam armas, armaduras ou escudos |
| Lança | NPCs que negociam arcos, flechas, bolts ou lanças |
| Cifrão | NPCs com serviço de banco |
| Cruz | Templo de cada cidade |
| Exclamação | Baús de quest |

As posições saem dos dados do servidor (mapa, scripts de troca de andar, arquivos dos NPCs e `items.srv`):

```sh
python3 tools/generate-minimap-markers.py
```

Gere de novo quando o mapa ou os NPCs mudarem. O cliente lê o arquivo em [uiminimap.lua](../client/modules/gamelib/ui/uiminimap.lua) e cria só as marcações próximas da câmera, no andar atual. As setas aparecem a partir do zoom normal; lojas, bancos, templos e quests continuam visíveis com o mapa mais afastado. Elas não são gravadas nas configurações do jogador, então as marcações criadas por ele continuam funcionando como antes, e o menu do botão direito no minimapa tem a opção de esconder ou mostrar as marcações prontas. Ao montar a distribuição de produção, copie o arquivo para a pasta `data/` do cliente junto com o `minimap.otmm`.

## Launcher Windows

O [projeto do launcher](../launcher/AntigasLauncher/AntigasLauncher.csproj) usa Windows Forms, .NET 10 e runtime `win-x64`. Em Windows com o SDK .NET 10, execute na raiz do repositório:

```powershell
dotnet build launcher/AntigasLauncher/AntigasLauncher.csproj --configuration Release
dotnet build tools/ReleaseSigner/ReleaseSigner.csproj --configuration Release
```

Para publicar uma distribuição independente do runtime instalado:

```powershell
dotnet publish launcher/AntigasLauncher/AntigasLauncher.csproj --configuration Release --runtime win-x64 --self-contained true --output build/launcher-publish
```

O projeto já configura publicação em arquivo único. [build-release.ps1](../launcher/build-release.ps1) empacota uma distribuição de cliente fornecida separadamente; não compila o OTClient nem obtém os assets ausentes.

O launcher busca um manifesto por HTTPS e verifica sua assinatura ECDSA P-256 com a chave pública fixada em [ReleaseService.cs](../launcher/AntigasLauncher/ReleaseService.cs). Depois verifica o SHA-256 assinado do ZIP e valida os caminhos extraídos. O código restringe hosts e nomes de pacotes; publicar para outro domínio ou outra chave exige ajustar e distribuir um launcher compatível.

[tools/ReleaseSigner/](../tools/ReleaseSigner/) contém o assinador. A chave privada fica no armazenamento CNG do usuário Windows e não está incluída aqui. [release-public-key.txt](../launcher/release-public-key.txt) contém somente a chave pública de verificação. A assinatura dos pacotes é distinta da assinatura Authenticode de um executável Windows.

## Site PHP

[site/](../site/) contém páginas públicas, estilos, traduções e um manifesto de release. Cadastro e conta dependem da biblioteca privada externa `security.php` e de tabelas de banco que não estão integralmente incluídas aqui. A página inicial (`wiki.php`) funciona sem essas bibliotecas. A rota `coins.php` é uma página informativa sem compras: não carrega bibliotecas de pagamento, não cria pedidos e não exibe dados do recebedor nem códigos de cobrança.

`ANTIGAS_WEB_LIB` permite indicar o diretório dessas bibliotecas. Disponibilize implementações compatíveis e suas configurações privadas antes de executar as páginas; copiar somente `site/` não completa a instalação. Revise também os links e o manifesto de downloads para sua distribuição.

As referências em [infra/nginx/](../infra/nginx/) pressupõem uma infraestrutura específica. Revise caminhos, serviços e permissões ao adaptá-las. O [guia de infraestrutura](../infra/README.md) descreve o restante do diretório.
