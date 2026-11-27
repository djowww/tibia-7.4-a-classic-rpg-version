<?php
declare(strict_types=1);
// "Total views" counter for the footer.
// Stores a single number on disk: no IP addresses, cookies or user agents are kept.
// Bots, prefetches and non-GET requests are shown the total without adding to it.

function siteViewsFile(): string {
    $path = getenv('ANTIGAS_VIEWS_FILE');
    return is_string($path) && $path !== '' ? $path : '/var/lib/antigas-site/views.txt';
}

function siteViewIsHuman(): bool {
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'GET') { return false; }
    $purpose = strtolower(($_SERVER['HTTP_SEC_PURPOSE'] ?? '') . ' ' . ($_SERVER['HTTP_PURPOSE'] ?? '') . ' ' . ($_SERVER['HTTP_X_MOZ'] ?? ''));
    if (str_contains($purpose, 'prefetch') || str_contains($purpose, 'prerender')) { return false; }
    $agent = (string)($_SERVER['HTTP_USER_AGENT'] ?? '');
    if (!str_contains($agent, 'Mozilla/')) { return false; }
    return preg_match('/bot|crawl|spider|slurp|curl|wget|python|go-http|zgrab|headless|scan|http-client|java\/|okhttp|libwww|facebookexternalhit|preview|monitor|uptime|lighthouse|phantom|selenium|playwright|axios|censys|nmap|compatible;|iPhone OS 13_2_3/i', $agent) !== 1;
}

// Returns the total, counting this request once if it is a human page view. Null if the file is unavailable.
function siteViewsTotal(): ?int {
    static $total = false;
    if ($total !== false) { return $total; }
    $total = null;
    $handle = @fopen(siteViewsFile(), 'c+');
    if ($handle === false) { return null; }
    $count = siteViewIsHuman();
    if (flock($handle, $count ? LOCK_EX : LOCK_SH)) {
        $value = (int)trim((string)stream_get_contents($handle));
        if ($count) {
            $value++;
            ftruncate($handle, 0);
            rewind($handle);
            fwrite($handle, (string)$value);
            fflush($handle);
        }
        flock($handle, LOCK_UN);
        $total = max(0, $value);
    }
    fclose($handle);
    return $total;
}

function siteViewsHtml(): string {
    $total = siteViewsTotal();
    if ($total === null) { return ''; }
    $digits = str_pad((string)$total, 6, '0', STR_PAD_LEFT);
    $cells = '';
    foreach (str_split($digits) as $digit) { $cells .= '<b>' . $digit . '</b>'; }
    return '<p class="views-counter" aria-label="Total views: ' . number_format($total) . '">Total views <span class="views-digits" aria-hidden="true">' . $cells . '</span></p>';
}
