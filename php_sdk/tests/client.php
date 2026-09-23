<?php
/**
 * The client, in real processes: a `php -S` stands in for the ingest and
 * records what arrives; CLI scripts and a `php -S` web application fail in
 * the ways a live site does. "Exits 255 and still reports" is a claim about a
 * process, so it is tested on one.
 */

declare(strict_types=1);

require_once __DIR__ . '/../autoload.php';

use Citadel\Arm\Arm;

$sdk = dirname(__DIR__);
$record = tempnam(sys_get_temp_dir(), 'arm-record');

/** @return array{0: resource, 1: int} */
function serve(string $router, array $env): array
{
    $port = random_int(20000, 40000);
    $process = proc_open(
        [PHP_BINARY, '-S', "127.0.0.1:$port", $router],
        [0 => ['pipe', 'r'], 1 => ['file', '/dev/null', 'w'], 2 => ['file', '/dev/null', 'w']],
        $pipes,
        dirname($router),
        $env + getenv()
    );
    for ($i = 0; $i < 50; $i++) {
        $socket = @fsockopen('127.0.0.1', $port);
        if ($socket !== false) {
            fclose($socket);
            break;
        }
        usleep(50_000);
    }
    return [$process, $port];
}

/** @return list<array<string, mixed>> every capture recorded so far */
function received(string $record): array
{
    $captures = [];
    foreach (file($record, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        $batch = json_decode($line, true);
        foreach ($batch['body'] ?? [] as $capture) {
            $capture['_client'] = $batch['client'];
            $capture['_key'] = $batch['key'];
            $captures[] = $capture;
        }
    }
    return $captures;
}

/** @return array{code: int, out: string, err: string, ms: float} */
function script(string $body, string $ingest, array $ini = []): array
{
    $file = tempnam(sys_get_temp_dir(), 'arm-script') . '.php';
    file_put_contents($file, "<?php\nrequire " . var_export(dirname(__DIR__) . '/autoload.php', true) . ";\n"
        . "\\Citadel\\Arm\\Arm::init(['client_id' => 'client-a', 'ingest_key' => 'k', 'ingest_url' => " . var_export($ingest, true) . ", 'root' => " . var_export(sys_get_temp_dir(), true) . ", 'service' => 'cron']);\n"
        . $body);
    $args = [PHP_BINARY];
    foreach ($ini + ['display_errors' => 'stderr', 'log_errors' => '0'] as $k => $v) {
        $args[] = '-d';
        $args[] = "$k=$v";
    }
    $args[] = $file;
    $started = microtime(true);
    $process = proc_open($args, [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
    $out = stream_get_contents($pipes[1]);
    $err = stream_get_contents($pipes[2]);
    $code = proc_close($process);
    return ['code' => $code, 'out' => (string) $out, 'err' => (string) $err, 'ms' => (microtime(true) - $started) * 1000];
}

[$ingestProcess, $ingestPort] = serve(__DIR__ . '/fixtures/ingest.php', ['ARM_RECORD' => $record]);
$ingest = "http://127.0.0.1:$ingestPort";

// --------------------------------------------------------------------- CLI

file_put_contents($record, '');
$r = script("function load() { throw new \\LogicException('Config 12 is missing'); }\nload();\n", $ingest);
$c = received($record);
check('cli uncaught: exit status stays 255', $r['code'] === 255, "got {$r['code']}");
check('cli uncaught: PHP\'s own message still printed', str_contains($r['err'], 'PHP Fatal error:  Uncaught LogicException: Config 12 is missing'), $r['err']);
check('cli uncaught: one capture arrived', count($c) === 1, (string) count($c));
check('cli uncaught: shaped as a php capture', ($c[0]['source'] ?? '') === 'php' && ($c[0]['operation'] ?? '') === 'uncaught_exception' && ($c[0]['severity'] ?? '') === 'critical' && ($c[0]['errorType'] ?? '') === 'LogicException' && ($c[0]['feature'] ?? '') === 'cron');
check('cli uncaught: client id and key in headers', ($c[0]['_client'] ?? '') === 'client-a' && ($c[0]['_key'] ?? '') === 'k');
check('cli uncaught: stack starts at the throw site, relative to the root', str_starts_with((string) ($c[0]['stackTrace'] ?? ''), 'arm-script') && !str_contains((string) $c[0]['stackTrace'], sys_get_temp_dir() . '/'), (string) ($c[0]['stackTrace'] ?? ''));

file_put_contents($record, '');
$r = script("ini_set('memory_limit', '16M');\n\$a = [];\nwhile (true) { \$a[] = str_repeat('x', 1024 * 1024); }\n", $ingest);
$c = received($record);
check('memory exhaustion: PHP still dies with 255', $r['code'] === 255, "got {$r['code']}");
check('memory exhaustion: reported as a fatal from the reserve', ($c[0]['operation'] ?? '') === 'fatal_error' && ($c[0]['errorType'] ?? '') === 'E_ERROR' && str_contains((string) ($c[0]['message'] ?? ''), 'Allowed memory size'), json_encode($c));

file_put_contents($record, '');
$r = script("\$a = file_get_contents('/nonexistent/one');\n\$b = @file_get_contents('/nonexistent/two');\necho 'done';\n", $ingest);
$c = received($record);
check('warning: the script carries on', $r['code'] === 0 && $r['out'] === 'done');
check('warning: PHP\'s standard handler still prints it', str_contains($r['err'], 'Warning: file_get_contents(/nonexistent/one)'), $r['err']);
check('warning: captured once, and the @-suppressed one not at all', count($c) === 1 && ($c[0]['operation'] ?? '') === 'php_error' && ($c[0]['errorType'] ?? '') === 'E_WARNING' && ($c[0]['severity'] ?? '') === 'low', json_encode($c));

file_put_contents($record, '');
$r = script("set_exception_handler(function (\$e) { echo 'app handled: ', \$e->getMessage(); });\n"
    . "\\Citadel\\Arm\\Arm::reset();\n\\Citadel\\Arm\\Arm::init(['client_id' => 'client-a', 'ingest_key' => 'k', 'ingest_url' => " . var_export($ingest, true) . "]);\n"
    . "throw new \\DomainException('mine');\n", $ingest);
check('an application\'s own handler still runs', str_contains($r['out'], 'app handled: mine'), $r['out'] . $r['err']);
check('...and the capture still arrives', count(array_filter(received($record), fn ($x) => ($x['errorType'] ?? '') === 'DomainException')) === 1);

file_put_contents($record, '');
$r = script("try { \\Citadel\\Arm\\Arm::instance()->monitor('nightly-invoices', function () { throw new \\RuntimeException('SMTP down'); }); } catch (\\RuntimeException \$e) { echo 'rethrown: ', \$e->getMessage(); }\n", $ingest);
$c = received($record);
check('monitor: the job\'s exception is rethrown unchanged', $r['out'] === 'rethrown: SMTP down', $r['out']);
check('monitor: reported under the job\'s name', ($c[0]['feature'] ?? '') === 'job' && ($c[0]['operation'] ?? '') === 'nightly-invoices');

file_put_contents($record, '');
$r = script("\\Citadel\\Arm\\Arm::instance()->captureException(new \\Exception(\"bad bytes \\xff\\xfe here\"));\n", $ingest);
$c = received($record);
check('invalid UTF-8 in a message does not lose the batch', count($c) === 1 && str_contains((string) $c[0]['message'], 'bad bytes'), json_encode($c));

$r = script("function f() { throw new \\Error('offline'); }\nf();\n", 'http://10.255.255.1:81', []);
check('ingest unreachable: still 255, within the timeout', $r['code'] === 255 && $r['ms'] < 4000, "{$r['code']} in {$r['ms']} ms");

// --------------------------------------------------------------------- web

file_put_contents($record, '');
[$appProcess, $appPort] = serve(__DIR__ . '/fixtures/app.php', ['ARM_INGEST' => $ingest]);
$get = static function (string $path) use ($appPort): int {
    $context = stream_context_create(['http' => ['ignore_errors' => true, 'timeout' => 5]]);
    @file_get_contents("http://127.0.0.1:$appPort$path", false, $context);
    return (int) explode(' ', $http_response_header[0] ?? 'HTTP/1.1 0')[1];
};
$statuses = [$get('/boom?token=secret'), $get('/fail'), $get('/slow'), $get('/ok')];
usleep(300_000);
$c = received($record);
$byOperation = [];
foreach ($c as $capture) {
    $byOperation[$capture['operation']] = $capture;
}
check('web: the host\'s answers are unchanged', $statuses === [500, 502, 200, 200], json_encode($statuses));
check('web: exactly an uncaught exception, a 5xx and a slow request', array_keys($byOperation) == ['uncaught_exception', 'http_5xx', 'slow_request'] || count($byOperation) === 3 && isset($byOperation['uncaught_exception'], $byOperation['http_5xx'], $byOperation['slow_request']), json_encode(array_keys($byOperation)));
check('web: the thrown request is not also reported as a bare 5xx', count($c) === 3, (string) count($c));
$request = $byOperation['uncaught_exception']['context']['request'] ?? [];
check('web: request context is method, route and path — no query', ($request['method'] ?? '') === 'GET' && ($request['path'] ?? '') === '/boom' && ($request['route'] ?? '') === '/boom' && !str_contains(json_encode($c), 'secret'), json_encode($request));
check('web: release, environment and service carried', ($byOperation['uncaught_exception']['appVersion'] ?? '') === '2026.09.23' && ($byOperation['uncaught_exception']['environment'] ?? '') === 'production' && ($byOperation['uncaught_exception']['feature'] ?? '') === 'bookings');
check('web: the 5xx names the answer', ($byOperation['http_5xx']['message'] ?? '') === 'GET /fail answered 502', (string) ($byOperation['http_5xx']['message'] ?? ''));
check('web: stack relative to the application root', str_starts_with((string) ($byOperation['uncaught_exception']['stackTrace'] ?? ''), 'tests/fixtures/app.php('), (string) ($byOperation['uncaught_exception']['stackTrace'] ?? ''));

proc_terminate($appProcess);
proc_terminate($ingestProcess);
@unlink($record);
