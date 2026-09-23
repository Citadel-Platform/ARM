<?php

declare(strict_types=1);

namespace Citadel\Arm;

use Psr\Log\LoggerInterface;
use Psr\Log\LoggerTrait;
use Psr\Log\LogLevel;

/**
 * A PSR-3 logger that reports error-level entries to ARM and passes every
 * entry on to the application's own logger unchanged. Needs `psr/log`; the
 * rest of this package does not.
 *
 *     $logger = new \Citadel\Arm\ArmLogger(Arm::instance(), $monolog);
 *
 * An entry with an `exception` in its context is reported as that exception;
 * any other is reported by its message, uninterpolated — `{placeholders}` stay
 * placeholders, so one fault is one issue and no context value leaves.
 */
final class ArmLogger implements LoggerInterface
{
    use LoggerTrait;

    private const RANK = [
        LogLevel::DEBUG => 0, LogLevel::INFO => 1, LogLevel::NOTICE => 2, LogLevel::WARNING => 3,
        LogLevel::ERROR => 4, LogLevel::CRITICAL => 5, LogLevel::ALERT => 6, LogLevel::EMERGENCY => 7,
    ];

    public function __construct(
        private readonly ?Arm $arm,
        private readonly ?LoggerInterface $inner = null,
        private readonly string $minimumLevel = LogLevel::ERROR,
    ) {
    }

    /** @param array<string, mixed> $context */
    public function log($level, string|\Stringable $message, array $context = []): void
    {
        try {
            $rank = self::RANK[(string) $level] ?? 4;
            if ($this->arm !== null && $rank >= (self::RANK[$this->minimumLevel] ?? 4)) {
                $severity = $rank >= 5 ? 'critical' : ($rank === 4 ? 'serious' : 'moderate');
                $exception = $context['exception'] ?? null;
                if ($exception instanceof \Throwable) {
                    $this->arm->captureException($exception, ['operation' => 'log', 'severity' => $severity, 'category' => 'log', 'tags' => ['level' => (string) $level]]);
                } else {
                    $this->arm->captureMessage((string) $message, ['severity' => $severity, 'tags' => ['level' => (string) $level]]);
                }
            }
        } catch (\Throwable) {
            // Never into the host.
        }
        $this->inner?->log($level, $message, $context);
    }
}
