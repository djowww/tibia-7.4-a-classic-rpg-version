<?php
declare(strict_types=1);
header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-cache');
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('Referrer-Policy: strict-origin-when-cross-origin');
header("Content-Security-Policy: default-src 'self'; img-src 'self' data:; style-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'");
require __DIR__ . '/i18n.php';
require __DIR__ . '/visit-counter.php';
siteStartI18n('pt');
// This page is English only, by the owner's choice.
$GLOBALS['antigasLanguage'] = 'en';
function sysEscape(string $value): string { return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); }
// Page text lives here (pt kept for reference, en shown) so the shared translation file stays untouched.
function sysL(array $text): string { return $text[1]; }
// Big screenshots read better at full width, below the text.
$wideShots = ['tela-larga.jpg', 'market.jpg'];
$github = 'https://github.com/djowww/tibia-7.4-a-classic-rpg-version';
$discord = 'https://discord.gg/CVneyh53mZ';

// Each system: id, [title pt, en], [text pt, en], command, images [[file, alt pt, alt en]], coming in the next update.
$groups = [
    [['Progresso do personagem', 'Character progress'], [
        ['bonus-online', ['Bônus online', 'Online bonus'],
            ['Cada hora cheia online, sem sair, dá +0,2% de experiência e de skills, até +5%. Sair antes de completar a hora não conta aquela hora. O bônus fica salvo no personagem.',
             'Every full hour online in a row: +0.2% experience and skills, up to +5%. Saved on your character.'], '', [], false],
        ['bestiary', ['Bestiary', 'Bestiary'],
            ['Cada monstro tem um contador de abates. Ao chegar a 1.000 abates de uma criatura, o Bestiary dela fica completo e você ganha +0,2% de experiência para sempre. Monstros invocados não contam. Acompanhe pela Game Wiki.',
             '1,000 kills of a creature completes its entry: +0.2% experience forever. Summons do not count. Track it in the Game Wiki.'], '',
            [['wiki-bestiary.jpg', 'Bestiary na Game Wiki: abates, locais no mapa e loot', 'Bestiary in the Game Wiki: kills, map spots and loot']], false],
        ['conquistas', ['Conquistas', 'Achievements'],
            ['Metas de passos andados (dão velocidade), monstros mortos (+dano), mortes (perde menos na morte), frags, levels 20 a 200 (pergaminho de +25% XP por 1 hora) e skills 40 a 120 (arma de treino). Se faltar espaço, o prêmio espera e você resgata depois na janela Achievements.',
             'Goals for steps (speed), monster kills (damage), deaths (less death loss), frags, levels 20-200 (+25% XP scroll, 1 hour) and skills 40-120 (training weapon). No room? Claim it later in the Achievements window.'], '',
            [['conquistas.jpg', 'Janela de Achievements com ranks, contadores e bônus', 'Achievements window with ranks, counters and bonuses']], false],
        ['baus', ['Baús de exploração', 'Exploration chests'],
            ['Cada região tem um baú escondido: Thais, Carlin, Kazordoon, Ab\'Dendriel, Edron, Darashia, Venore, Ankrahmun, Rookgaard e Port Hope. O lugar muda a cada reinício do servidor. Ao abrir, escolha um prêmio: ouro (0,4% da sua experiência), mana (+0,2% e regeneração extra) ou vida (+0,3% e regeneração extra). Cada baú vale uma vez por personagem.',
             'One hidden chest per region (Thais, Carlin, Kazordoon, Ab\'Dendriel, Edron, Darashia, Venore, Ankrahmun, Rookgaard, Port Hope). The spot changes every restart. Pick one reward: gold (0.4% of your experience), mana (+0.2% and regen) or health (+0.3% and regen). Once per character.'], '',
            [['bau-exploracao.gif', 'Janela do baú escondido com as três escolhas', 'Hidden chest window with the three choices']], true],
    ]],
    [['Caça', 'Hunting'], [
        ['game-wiki', ['Game Wiki', 'Game Wiki'],
            ['Um livro dentro do cliente (botão Wiki no inventário) com Bestiary, Itempedia e Hunting Guide. O Hunting Guide sugere lugares de caça pela sua vocação e level, solo ou em party, e o botão Map mostra o local no minimapa.',
             'Wiki button on the inventory: Bestiary, Itempedia and Hunting Guide. The Hunting Guide picks spots for your vocation and level; Map shows them on the minimap.'], '',
            [['wiki-hunting.jpg', 'Hunting Guide filtrado por vocação e level', 'Hunting Guide filtered by vocation and level']], true],
        ['noite-de-caca', ['Noite de caça', 'Hunting night'],
            ['Das 19:00 às 05:00 do jogo: +25% de experiência e de loot, monstros batem 10% mais forte e renascem 25% mais rápido. O servidor avisa no chat quando a noite começa e termina.',
             '19:00 to 05:00 game time: +25% experience and loot, monsters hit 10% harder and respawn 25% faster. Announced in chat.'], '!time',
            [['chat-noite-cansaco.jpg', 'Chat mostrando a hora, o aviso da noite de caça e o !fatigue', 'Chat showing the time, the hunting night notice and !fatigue']], true],
        ['cansaco', ['Cansaço por criatura', 'Creature fatigue'],
            ['Caçar sempre o mesmo bicho cansa: a cada 20 abates da mesma criatura você ganha 1% menos experiência dela, até -40%. O cansaço some sozinho (100 abates por hora). Trocar de caça resolve na hora.',
             'Every 20 kills of the same creature: -1% experience from it, down to -40%. Recovers 100 kills per hour. Switch hunts to avoid it.'], '!fatigue', [], true],
        ['respawn', ['Respawn conforme o online', 'Respawn by players online'],
            ['Com poucos jogadores os monstros renascem no tempo normal. Quanto mais gente online, mais rápido: até a metade do tempo com 150 jogadores.',
             'More players online, faster respawn: normal up to 10 players, half the time at 150.'], '', [], true],
        ['party', ['Party com vocações diferentes', 'Mixed-vocation party'],
            ['Com experiência compartilhada ligada, a party ganha bônus pela variedade de vocações: 1 vocação +20%, 2 vocações +30%, 3 vocações +60% e as 4 vocações +100%.',
             'With shared experience on: 1 vocation +20%, 2 vocations +30%, 3 vocations +60%, all 4 +100%.'], '!share', [], false],
        ['raridade', ['Raridade de loot e canal Loot', 'Loot rarity and Loot channel'],
            ['Equipamentos que caem de monstros podem vir com raridade: incomum, raro, épico, lendário ou mítico. A cor e as marcas aparecem no inventário, nos containers e no chão, e o tooltip mostra os atributos. O canal Loot lista cada drop com a cor da raridade.',
             'Monster equipment can drop as uncommon, rare, epic, legendary or mythic, with color and marks in bags and on the ground. The Loot channel shows every drop in its rarity color.'], '',
            [['raridade-tooltip.jpg', 'Tooltip de um item lendário', 'Tooltip of a legendary item'], ['canal-loot.jpg', 'Canal Loot com os itens coloridos por raridade', 'Loot channel with items colored by rarity']], false],
    ]],
    [['Mundo', 'World'], [
        ['dia-e-noite', ['Dia e noite', 'Day and night'],
            ['Um dia do jogo dura 4 horas reais: 2 horas de dia e 2 de noite, com amanhecer e entardecer. A hora segue o relógio e não reinicia com o servidor. Fale !time para ver a hora do jogo.',
             'A game day lasts 4 real hours: 2 of day, 2 of night, with dawn and dusk. Survives restarts.'], '!time',
            [['dia-noite.gif', 'O templo de Rookgaard do meio-dia à meia-noite', 'Rookgaard temple from noon to midnight']], true],
        ['luz', ['Luz clássica e tochas', 'Classic light and torches'],
            ['A luz do jogo fica sempre ligada, como no 7.4: lugar escuro é escuro de verdade. Para compensar, as tochas acesas duram o dobro.',
             'Light is always on, like 7.4: dark places stay dark. Torches last twice as long.'], '',
            [['luz-sem-tocha.jpg', 'Subsolo sem tocha', 'Underground without a torch'], ['luz-com-tocha.jpg', 'Subsolo com tocha acesa', 'Underground with a lit torch']], true],
        ['minimapa', ['Minimapa completo', 'Full minimap'],
            ['O minimapa já vem com o mundo inteiro e marcações de templos, bancos, lojas, quests e escadas. Clique com o botão direito no minimapa para esconder ou mostrar as marcações.',
             'The whole world is revealed, with markers for temples, banks, shops, quests and stairs. Right-click to hide them.'], '',
            [['minimapa.jpg', 'Minimapa de Thais com as marcações', 'Thais minimap with markers']], false],
        ['casas', ['Aluguel semanal das casas', 'Weekly house rent'],
            ['O aluguel é cobrado toda semana (um quarto do valor mensal). Sem dinheiro no banco, você recebe avisos por 7 dias; depois disso perde a casa e os itens vão para o seu depot.',
             'Rent is charged weekly (a quarter of the monthly price). No money in the bank: 7 days of warnings, then the house is lost and your items go to your depot.'], '!buyhouse · !leavehouse', [], true],
    ]],
    [['Comércio', 'Trading'], [
        ['trade-npc', ['Trade e balão dos NPCs', 'NPC trade and chat balloon'],
            ['Clique no balão em cima do NPC ou com o botão direito nele para dizer hi (o botão direito nunca ataca NPC). Depois diga trade: abre uma janela com preço, peso e quantidade, que avisa se a compra não cabe no peso ou na mochila.',
             'Click the balloon or right-click an NPC to say hi (never attacks). Say trade for a window with price, weight and amount; it warns when items do not fit.'], 'hi · trade',
            [['balao-npc.jpg', 'Balão de conversa em cima do NPC', 'Chat balloon above an NPC'], ['trade-npc.jpg', 'Janela de trade com NPC', 'NPC trade window']], false],
        ['preco-dinamico', ['Preço dinâmico dos NPCs', 'Dynamic NPC prices'],
            ['Quando muita gente vende o mesmo item, o NPC paga menos por ele: -1% a cada 20 unidades vendidas no servidor, até a metade do preço. O preço volta ao normal com o tempo (metade da queda some a cada 3 horas). A janela de trade sempre mostra o preço do momento.',
             'NPCs pay 1% less for every 20 units of an item sold on the server, down to half price. Half of the drop recovers every 3 hours.'], '', [], true],
        ['market', ['Market', 'Market'],
            ['Crie ofertas de compra e venda em gold ou Antigas Coins, com negociação parcial e histórico. Gold vai para o banco; itens e coins chegam no depot da sua cidade. Itens raros não entram no Market.',
             'Buy and sell offers in gold or Antigas Coins, with partial trades and history. Gold goes to the bank, items and coins to your depot. Rare items cannot be listed.'], '',
            [['market.jpg', 'Market com ofertas de compra e venda', 'Market with buy and sell offers']], false],
        ['correio', ['Correio com etiqueta', 'Mail with a label'],
            ['Parcel e letter só entram na mailbox com etiqueta válida (nome de um personagem que existe e a cidade). Sem etiqueta, o item continua com você em vez de ficar perdido em cima da caixa.',
             'Parcels and letters need a valid label (character name and town), or they stay with you.'], '', [], true],
    ]],
    [['PvP', 'PvP'], [
        ['bounty', ['Recompensa por PK', 'PK bounty'],
            ['Quem mata um jogador de forma injusta paga 100 gold por level do próprio assassino (do banco, depois da mochila), e esse valor vira recompensa pela cabeça dele. Quem matar o assassino recebe tudo no banco. Fale !bounty para ver os 10 mais procurados.',
             'An unjust kill costs the killer 100 gold per their level (bank first, then backpack). That gold becomes a bounty on them, paid to whoever kills them. !bounty lists the top 10.'], '!bounty', [], true],
    ]],
    [['Cliente e segurança', 'Client and safety'], [
        ['tela-larga', ['Tela larga', 'Widescreen'],
            ['Em monitores largos o jogo mostra mais área do mapa dos lados, sem esticar os sprites.',
             'Wide monitors see more map on the sides, no stretched sprites.'], '',
            [['tela-larga.jpg', 'Caça em tela larga', 'Hunting in widescreen']], false],
        ['skills', ['Janela de Skills', 'Skills window'],
            ['Barras discretas, o tempo restante de comida e quanto de vida e mana você recupera, com a origem de cada parte.',
             'Shows the time left on food and how much health and mana you regenerate, and from where.'], '',
            [['skills.jpg', 'Janela de Skills com comida e regeneração', 'Skills window with food and regeneration']], false],
        ['diario', ['Diário de quests', 'Quest journal'],
            ['O Quest Log guarda as quests e missões que o seu personagem já descobriu, com notas do que você aprendeu. Ele só mostra o que você conhece, sem spoilers.',
             'Keeps the quests and missions you have found, with notes. No spoilers.'], '', [], false],
        ['save', ['Save automático', 'Autosave'],
            ['O servidor salva cada personagem a cada 5 minutos, e também ao fechar um trade entre jogadores e ao mandar um parcel. Se o servidor cair, você perde no máximo alguns minutos.',
             'Every character is saved every 5 minutes, after each player trade and after sending a parcel.'], '', [], true],
        ['anti-bot', ['Detecção de bots', 'Bot detection'],
            ['O servidor percebe jogo automatizado e avisa a equipe, que decide o que fazer. Se aparecer uma pergunta de conta na sua tela, responda com !humano e o número.',
             'Automated play alerts the staff. If a math question pops up, answer with !human and the number.'], '!human', [], true],
    ]],
];
?>
<!doctype html>
<html lang="<?= sysEscape(siteLanguageTag()) ?>">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="<?= sysEscape(sysL(['Os sistemas próprios do servidor Tibia 7.4, explicados em poucas linhas.', 'The custom systems of the Tibia 7.4 server, explained in a few lines.'])) ?>">
  <link rel="canonical" href="https://tibia74.tech/sistemas.php">
  <title><?= sysEscape(sysL(['Sistemas custom', 'Custom systems'])) ?> — Tibia 7.4</title>
  <link rel="stylesheet" href="/classic-2004.css?v=20260924-1">
  <link rel="stylesheet" href="/language.css?v=security-20260928">
  <link rel="stylesheet" href="/classic-refinement.css?v=classic-20261127-2">
  <link rel="stylesheet" href="/wiki.css?v=project-home-20261023-1">
  <link rel="stylesheet" href="/sistemas.css?v=20261127-1">
</head>
<body class="wiki-page project-home systems-page">
  <a class="skip-link" href="#wiki-content"><?= siteT('Skip to content') ?></a>
  <div class="skyline">
    <header class="masthead">
      <a class="wordmark" href="/" aria-label="Tibia 7.4 — <?= siteT('Home') ?>"><span>Tibia 7.4</span><i>A CLASSIC RPG VERSION</i></a>
      <p class="motto"><?= siteT('Open source project') ?></p>
    </header>
    <nav class="topnav" aria-label="<?= siteT('Main navigation') ?>">
      <a href="/"><?= siteT('Home') ?></a><a href="/#novidades"><?= siteT('News') ?></a><a href="/#guia"><?= siteT('Player guide') ?></a><a href="/sistemas.php" aria-current="page"><?= sysEscape(sysL(['Sistemas custom', 'Custom systems'])) ?></a><a href="/#download"><?= siteT('Download') ?></a><a href="<?= sysEscape($github) ?>">GitHub</a><a href="<?= sysEscape($discord) ?>">Discord</a>
    </nav>
  </div>
  <div class="layout wiki-layout">
    <aside class="sidebar wiki-sidebar">
      <nav class="stone-menu" aria-label="<?= sysEscape(sysL(['Sistemas custom', 'Custom systems'])) ?>">
        <?php foreach ($groups as [$groupTitle, $systems]): ?>
        <h2><?= sysEscape(sysL($groupTitle)) ?></h2>
        <?php foreach ($systems as [$id, $title]): ?><a href="#<?= sysEscape($id) ?>"><?= sysEscape(sysL($title)) ?></a><?php endforeach; ?>
        <div class="side-rule" aria-hidden="true"></div>
        <?php endforeach; ?>
        <a href="/#guia"><?= siteT('Player guide') ?></a>
      </nav>
    </aside>
    <main class="paper wiki-paper" id="wiki-content" tabindex="-1">
      <section class="page-title project-title"><h1><?= sysEscape(sysL(['Sistemas custom', 'Custom systems'])) ?></h1><p class="project-subtitle"><?= sysEscape(sysL(['O que este servidor tem de diferente do 7.4', 'What this server adds to 7.4'])) ?></p></section>
      <div class="wiki-callout project-welcome"><div><p><?= sysEscape(sysL(['O mapa e as fórmulas seguem o 7.4. Estes são os sistemas que criamos por cima, cada um em poucas linhas.', 'The map and formulas follow 7.4. These are the systems built on top.'])) ?></p><p class="project-small"><?= sysL(['Os marcados com <b class="sys-new">Novo</b> chegam ao servidor oficial no próximo update.', 'Systems marked <b class="sys-new">New</b> reach the official server in the next update.']) ?></p></div></div>
      <details class="classic-index wiki-index"><summary><?= sysEscape(sysL(['Índice', 'Index'])) ?></summary><nav aria-label="<?= sysEscape(sysL(['Índice', 'Index'])) ?>"><?php foreach ($groups as [$groupTitle, $systems]): foreach ($systems as [$id, $title]): ?><a href="#<?= sysEscape($id) ?>"><?= sysEscape(sysL($title)) ?></a><?php endforeach; endforeach; ?></nav></details>
      <?php foreach ($groups as [$groupTitle, $systems]): ?>
      <h2 class="news-ribbon sys-group"><span><?= sysEscape(sysL($groupTitle)) ?></span></h2>
      <?php foreach ($systems as [$id, $title, $text, $command, $images, $isNew]): ?>
      <section class="wiki-entry sys-entry<?= count($images) === 1 && !in_array($images[0][0], $wideShots, true) ? ' sys-has-side' : '' ?>" id="<?= sysEscape($id) ?>">
        <div class="sys-text">
          <h3><?= sysEscape(sysL($title)) ?><?php if ($isNew): ?> <b class="sys-new"><?= sysEscape(sysL(['Novo', 'New'])) ?></b><?php endif; ?></h3>
          <p><?= sysEscape(sysL($text)) ?></p>
          <?php if ($command !== ''): ?><p class="sys-cmd"><?= sysEscape(sysL(['Comando', 'Command'])) ?>: <code><?= sysEscape($command) ?></code></p><?php endif; ?>
        </div>
        <?php if ($images): ?><div class="sys-shots"><?php foreach ($images as [$file, $altPt, $altEn]): ?><figure><img src="/images/sistemas/<?= sysEscape($file) ?>" alt="<?= sysEscape(sysL([$altPt, $altEn])) ?>" loading="lazy"><figcaption><?= sysEscape(sysL([$altPt, $altEn])) ?></figcaption></figure><?php endforeach; ?></div><?php endif; ?>
      </section>
      <?php endforeach; ?>
      <?php endforeach; ?>
      <footer>Tibia 7.4 — A classic rpg version · <?= siteT('Independent community project, inspired by Tibia. Not affiliated with CipSoft.') ?><br><a href="<?= sysEscape($github) ?>">GitHub</a> · <a href="<?= sysEscape($github) ?>/blob/main/NOTICE.md"><?= siteT('Credits and licenses') ?></a><?= siteViewsHtml() ?></footer>
    </main>
  </div>
</body>
</html>
