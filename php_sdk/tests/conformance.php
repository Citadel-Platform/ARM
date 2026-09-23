<?php
/**
 * The PHP port against `arm/contract/conformance.json`, which `arm/tooling_core`
 * generates. Every expected value must be reproduced exactly; if not, a PHP
 * server and a Dart app disagree about what one fault is. Feature 1.6.1.
 */

declare(strict_types=1);

require __DIR__ . '/../autoload.php';

use Citadel\Arm\Contract;

$conformance = json_decode((string) file_get_contents(__DIR__ . '/../../contract/conformance.json'), true, 512, JSON_THROW_ON_ERROR);

check('the conformance file has cases', count($conformance['fingerprints']) >= 8 && count($conformance['sanitizer']) >= 5);

foreach ($conformance['fingerprints'] as $c) {
    $fingerprint = Contract::fingerprint($c['feature'], $c['operation'], $c['errorType'], $c['message'], $c['stack']);
    check("fingerprint: {$c['name']}", $fingerprint === $c['expected']['fingerprint'], $fingerprint . "\n  expected " . $c['expected']['fingerprint']);
    check("issue id: {$c['name']}", Contract::issueId($c['expected']['fingerprint']) === $c['expected']['issueId']);
}

foreach ($conformance['sanitizer'] as $c) {
    $actual = json_encode(Contract::sanitize($c['input']), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    $expected = json_encode($c['expected'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    check("sanitizer: {$c['name']}", $actual === $expected, "$actual\n  expected $expected");
}
