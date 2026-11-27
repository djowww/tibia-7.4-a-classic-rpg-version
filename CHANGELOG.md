# Histórico de mudanças

As mudanças de cada dia de trabalho, da mais recente para a mais antiga. As notícias para jogadores também aparecem no [site](https://tibia74.tech/).

## Em desenvolvimento (na `main`, ainda não no servidor oficial)

### 2026-11-27

- **Launcher novo com Guardian:** o launcher ganhou a tela nova (muralha com tochas, notícias do site e jogadores online) e o Guardian. Antes de abrir o jogo, ele confere cada arquivo do cliente com a lista assinada da versão, procura bots conhecidos abertos no computador e pede ao servidor um token para a sessão, que o cliente apresenta ao entrar. O que o launcher informa soma pontos no detector de bots do servidor. Continua sem punição automática: só a equipe é avisada.
- **Raridade com aura de fundo:** o slot de um item com raridade acende por trás do sprite na cor do nível, com borda fina e um entalhe por nível na borda de baixo; lendário e mítico pulsam devagar. O raio sobre o item saiu do slot e do chão, onde entrou um halo suave. O tooltip mostra o nome do nível na cor dele.
- **Tela de personagem nova:** depois do login, o personagem escolhido aparece em destaque no templo da cidade dele, com o cenário do próprio jogo ao fundo, e a lista mostra outfit, level e vocação de cada personagem. O servidor passa a mandar esses dados na lista de personagens para o cliente novo; clientes antigos continuam funcionando.
- **NPCs falam sozinhos:** quando há jogador por perto e ninguém está conversando com eles, os NPCs soltam de tempos em tempos um rumor, uma dica de quest ou um comentário sobre o trabalho, em amarelo no mapa (cerca de 1.000 falas em inglês, algumas só de noite). Monstros continuam em laranja.
- **Luzes das cidades à noite:** postes, lampiões de parede e tochas fixas perto dos templos acendem sozinhos às 17:30 do jogo e só apagam às 07:00; à noite ninguém consegue apagá-los (a equipe pode). De dia voltam ao estado original do mapa.
- **Inspect bot para a equipe:** no menu do botão direito sobre um jogador, GM e GOD têm "Inspect bot" (janela com a chance de bot, sinais e detalhes do detector) e "Start bot check".
- **Noite de caça:** das 19:00 às 05:00 do jogo, os monstros dão 25% a mais de XP e de loot, nascem 25% mais rápido e batem 10% mais forte. O servidor avisa no começo e no fim da noite.
- **Cansaço por criatura:** caçar sempre o mesmo monstro reduz a XP dele aos poucos (até -40%), e o cansaço passa sozinho com o tempo. `!fatigue` mostra o cansaço atual.
- **Preço dinâmico nos NPCs:** quanto mais um item é vendido aos NPCs no servidor, menos eles pagam por ele (até a metade do preço), e o preço volta ao normal com o tempo. A taxa de ouro dos monstros voltou para 1x.
- **Recompensa por PK:** quem mata sem justificativa paga 100 gp por level, e o valor vira recompensa para quem matar o assassino. `!bounty` mostra os 10 maiores.
- **Aluguel semanal:** as casas cobram o aluguel toda semana; depois de 7 avisos sem pagamento, a casa é perdida e os itens vão para o depot.
- **Respawn pelo número de jogadores:** com poucos jogadores online os monstros nascem no tempo normal, e com mais gente o respawn fica mais rápido.
- **Correções do teste com bots:** pagar o aluguel zera os avisos, quedas do servidor não contam como aviso extra, a recompensa do bounty é salva na hora e os descontos de cansaço e de preço arredondam certo.
- **Removidos:** o Bosstiary da Game Wiki e o sistema de água (beber água não dá mais mana e a linha Water saiu da janela Skills). Beber da garrafa continua como no 7.4 original.
- **Ping:** o próximo passo sai assim que o servidor confirma o anterior, o que deixa a andada mais contínua com ping alto. O servidor desliga o atraso de agrupamento de pacotes (TCP_NODELAY) em cada conexão.

### 2026-11-26

- **Estabilidade:** limite de 100 níveis para bolsas dentro de bolsas, pedidos do Bestiary com limite de profundidade e de frequência, e proteções em troca de itens, zona de criatura e transformação de itens.
- **Denúncias (Ctrl+R):** só a staff fecha a denúncia de outro jogador, e a denúncia de quem sai do jogo é cancelada.
- **`!frags`:** as contagens da semana e do mês agora aparecem certas.
- **Cliente:** fechar um canal de chat não gera mais erro, e a descrição de itens com cargas não repete o ponto final.
- **Save automático:** todos os jogadores e casas são salvos a cada 5 minutos, em partes pequenas a cada 10 segundos para não travar o servidor. O personagem também é salvo ao fechar uma troca e ao mandar um parcel, o que evita itens clonados se o servidor cair.
- **Mailbox:** parcel ou carta sem etiqueta válida (personagem e cidade que existem) não é aceito e fica com quem tentou mandar.
- **Conexões:** quando faltam arquivos abertos no servidor (muitas conexões ao mesmo tempo), a porta continua aceitando logins em vez de fechar por 15 segundos.
- **Tela larga:** ao entrar no jogo, o mapa já aparece na largura certa, sem a piscada da visão clássica 15x11.
- **Dia e noite:** um dia do jogo dura 4 horas reais, com 2 horas de dia e 2 de noite, e o céu clareia e escurece aos poucos no amanhecer e no entardecer. `!time` mostra a hora do jogo.
- **Servidor local:** o `compose.yaml` reinicia o servidor sozinho depois do server save.

### 2026-11-25

- **Baús de exploração:** um baú escondido em cada região (Thais, Carlin, Kazordoon, Ab'Dendriel, Edron, Darashia, Venore, Ankrahmun, Rookgaard e Port Hope). Quem encontra escolhe um bônus permanente para o personagem: ouro, mana ou vida.
- **Barras de skill** mais discretas na janela Skills, sem o contorno preto.
- **Regeneração na janela Skills:** mostra quanto de vida e mana o personagem recupera e de onde vem (comida e baús de exploração).
- **Luz clássica:** a iluminação fica sempre ligada, como no 7.4, e as tochas duram o dobro.
- **F1 para a equipe:** lista dos comandos de GM, montada pelo servidor a partir das talkactions.
- **Detecção de bots:** o servidor identifica comportamento automatizado e avisa a equipe.
- **Estabilidade:** correções de travamentos e abusos conhecidos do TFS e do OTClient, como containers acima da capacidade, criaturas removidas durante o combate e texto anônimo nos canais públicos.
- **Organização do repositório:** scripts próprios do projeto em pastas `custom/`; cliente, launcher e site na raiz (`client/`, `launcher/`, `site/`); infraestrutura em `infra/`; testes separados por linguagem em `tests/`.

## No servidor oficial

### 2026-11-24

- **Trade avisa antes de faltar espaço:** a janela mostra a capacidade e avisa quando a compra não cabe no peso ou na mochila, ou quando o troco vai cair no chão.
- **Água e comida por até 1 hora,** com o tempo restante nas linhas Food e Water da janela Skills.
- **Bônus de XP e skills** de volta, junto com os bônus de achievements e Bestiary.
- **Game Wiki (em desenvolvimento):** livro no cliente com Bestiary, Itempedia, Hunting Guide e Bosstiary.
- **Labirinto e alavanca do mapa original** voltaram a funcionar como no 7.4.

### 2026-11-23 (launcher v78)

- Servidor público de volta, com banco novo: as contas antigas precisam ser criadas de novo.
- **Trade com NPCs:** diga `hi` e depois `trade` para abrir a janela de compra e venda.
- **Balão de conversa** sobre os NPCs; clique direito cumprimenta em vez de atacar. NPCs têm barra azul na lista de batalha.
- **Mapa original do 7.4:** trainers, Yalahar, ilhas extras, arena e cavalos foram retirados.
- **Minimapa completo** com marcações de templos, bancos, lojas, quests e escadas.
- **Cliente só OpenGL e wide screen,** com andar mais fluido em ping alto e botão do Discord.

### 2026-10-23

- Pacote localhost para Windows: servidor, banco de teste e cliente em um só download, abertos pelo `Tibia74-Local.exe`.

### 2026-10-22

- Novo nome do projeto e repositório público, com os avisos de autoria e licença das bases preservados.
