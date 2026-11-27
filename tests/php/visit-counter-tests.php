<?php
declare(strict_types=1);
// The footer counter adds one per human page view and never counts bots, prefetches or POSTs.
$file = tempnam(sys_get_temp_dir(), 'views');
file_put_contents($file, '860');
putenv('ANTIGAS_VIEWS_FILE=' . $file);
$cases = [
    ['GET', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/140.0 Safari/537.36', '', 861],
    ['GET', 'Mozilla/5.0 (compatible; Googlebot/2.1)', '', 860],
    ['GET', 'curl/8.0', '', 860],
    ['POST', 'Mozilla/5.0 (Windows NT 10.0) Firefox/139.0', '', 860],
    ['GET', 'Mozilla/5.0 (Windows NT 10.0) Firefox/139.0', 'prefetch', 860],
];
foreach ($cases as [$method, $agent, $purpose, $expected]) {
    file_put_contents($file, '860');
    $code = '$_SERVER["REQUEST_METHOD"]=' . var_export($method, true) . ';$_SERVER["HTTP_USER_AGENT"]=' . var_export($agent, true)
        . ';$_SERVER["HTTP_SEC_PURPOSE"]=' . var_export($purpose, true) . ';require ' . var_export(__DIR__ . '/../../site/visit-counter.php', true)
        . ';echo siteViewsHtml();echo siteViewsHtml();';
    $html = (string)shell_exec(escapeshellarg(PHP_BINARY) . ' -r ' . escapeshellarg($code));
    $stored = (int)file_get_contents($file);
    if ($stored !== $expected) { unlink($file); throw new RuntimeException("$method $agent stored $stored, expected $expected"); }
    if (!str_contains($html, 'Total views: ' . number_format($expected))) { unlink($file); throw new RuntimeException('Counter HTML missing'); }
}
unlink($file);
echo 'Visit counter regression passed' . PHP_EOL;
