# Histórico de mudanças

As mudanças de cada dia de trabalho, da mais recente para a mais antiga. As notícias para jogadores também aparecem no [site](https://tibia74.tech/).

## Em desenvolvimento (na `main`, ainda não no servidor oficial)

### 2026-11-25

- **Baús de exploração:** um baú escondido em cada região (Thais, Carlin, Kazordoon, Ab'Dendriel, Edron, Darashia, Venore, Ankrahmun, Rookgaard e Port Hope). Quem encontra escolhe um bônus permanente para o personagem: ouro, mana ou vida.
- **Barras de skill** mais discretas na janela Skills, sem o contorno preto.
- **Regeneração na janela Skills:** mostra quanto de vida e mana o personagem recupera e de onde vem (comida, água e baús de exploração).
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
