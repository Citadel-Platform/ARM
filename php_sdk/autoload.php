<?php
/**
 * For an application without Composer — most custom PHP in this market:
 * `require '/path/to/citadel-arm/autoload.php';`. With Composer, its own
 * autoloader does the same from composer.json.
 */

declare(strict_types=1);

spl_autoload_register(static function (string $class): void {
    $prefix = 'Citadel\\Arm\\';
    if (strncmp($class, $prefix, strlen($prefix)) !== 0) {
        return;
    }
    $file = __DIR__ . '/src/' . str_replace('\\', '/', substr($class, strlen($prefix))) . '.php';
    if (is_file($file)) {
        require $file;
    }
});
