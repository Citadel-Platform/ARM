<?php
// A plain PHP application with ARM installed, served by `php -S`.
require __DIR__ . '/../../autoload.php';

\Citadel\Arm\Arm::init([
    'client_id' => 'client-a',
    'ingest_key' => 'arm-client-a-key',
    'ingest_url' => (string) getenv('ARM_INGEST'),
    'release' => '2026.09.23',
    'environment' => 'production',
    'service' => 'bookings',
    'root' => dirname(__DIR__, 2),
    'slow_ms' => 300,
]);

$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
if ($path === '/boom') {
    \Citadel\Arm\Arm::instance()?->setRoute('/boom');
    throw new \RuntimeException('Booking 4411 could not be confirmed');
}
if ($path === '/fail') {
    http_response_code(502);
    echo 'upstream down';
    return;
}
if ($path === '/slow') {
    usleep(500_000);
    echo 'slow';
    return;
}
echo 'ok';
