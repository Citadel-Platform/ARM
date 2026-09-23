<?php
/**
 * `php tests/run.php` — every test file here, no framework. Composer and
 * PHPUnit are not assumed: the client itself must install without them.
 */

declare(strict_types=1);

$GLOBALS['citadel_checks'] = 0;
$GLOBALS['citadel_failures'] = 0;

function check(string $name, bool $ok, string $detail = ''): void
{
    $GLOBALS['citadel_checks']++;
    if (!$ok) {
        $GLOBALS['citadel_failures']++;
        fwrite(STDERR, "FAIL: $name" . ($detail !== '' ? "\n  $detail" : '') . "\n");
    }
}

foreach (glob(__DIR__ . '/*.php') ?: [] as $file) {
    if (basename($file) !== 'run.php') {
        require $file;
    }
}

echo "{$GLOBALS['citadel_checks']} checks, {$GLOBALS['citadel_failures']} failed\n";
exit($GLOBALS['citadel_failures'] > 0 ? 1 : 0);
