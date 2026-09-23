<?php

declare(strict_types=1);

namespace Citadel\Arm;

/**
 * ARM for a PHP application (Feature 1.6.3).
 *
 * Captures uncaught exceptions, fatal errors, warnings, 5xx answers and slow
 * requests, and sends them to Citadel's shared ARM ingest with the client id
 * and the public ARM ingest key. The ingest groups them and writes the
 * client's own `citadel-arm`; this never touches Firestore.
 *
 *     require '/path/to/citadel-arm/autoload.php';   // or Composer
 *     \Citadel\Arm\Arm::init([
 *         'client_id'   => 'CLIENT_ID',
 *         'ingest_key'  => 'ARM_INGEST_KEY',
 *         'ingest_url'  => 'https://<arm-ingest>',
 *         'release'     => '2026.09.23',   // optional
 *         'environment' => 'production',   // optional
 *     ]);
 *
 * **It must never hurt the host.** Nothing here throws into the application;
 * PHP's own handling of an error — its log line, its 500, its exit — is left
 * exactly as it was; captures are sent once, at the end of the request, with
 * a two-second ceiling; and where PHP-FPM allows, the response is finished
 * for the visitor before anything is sent.
 */
final class Arm
{
    public const VERSION = '0.1.0';

    private const FATALS = E_ERROR | E_PARSE | E_CORE_ERROR | E_COMPILE_ERROR | E_USER_ERROR;
    private const DUPLICATE_WINDOW = 60.0;
    private const MAX_BATCH = 20;
    private const MAX_QUEUE = 100;

    private static ?self $instance = null;

    /** @var array<string, mixed> */
    private array $options;
    /** @var list<string> The root as given and as resolved, longest first. */
    private array $roots = [];
    private string $sessionId;
    /** @var list<array<string, mixed>> */
    private array $queue = [];
    /** @var array<string, array{at: float, suppressed: int}> */
    private array $seen = [];
    private int $sentThisRequest = 0;
    private bool $capturing = false;
    private bool $capturedThisRequest = false;
    /** @var callable|null */
    private $previousExceptionHandler = null;
    /** @var callable|null */
    private $previousErrorHandler = null;
    /** Freed at shutdown so a memory-exhaustion fatal still has room to be reported. */
    private ?string $reserve = null;
    private float $started;
    /** @var callable|null Tests only. */
    private $sender = null;

    /**
     * @param array{
     *   client_id: string, ingest_key: string, ingest_url: string,
     *   release?: string, environment?: string, service?: string, root?: string,
     *   capture_errors?: int, slow_ms?: int, max_captures?: int,
     *   finish_request?: bool, timeout_ms?: int, install_handlers?: bool
     * } $options
     */
    public static function init(array $options): self
    {
        if (self::$instance !== null) {
            return self::$instance;
        }
        self::$instance = new self($options);
        if (($options['install_handlers'] ?? true) !== false) {
            self::$instance->install();
        }
        return self::$instance;
    }

    /** The running instance, or null before init(). */
    public static function instance(): ?self
    {
        return self::$instance;
    }

    /** @param array<string, mixed> $options */
    public function __construct(array $options)
    {
        $this->options = $options + [
            'release' => null,
            'environment' => null,
            'service' => null,
            'root' => null,
            // Warnings and user errors; notices and deprecations are noise at
            // the volume a live site makes them.
            'capture_errors' => E_WARNING | E_USER_WARNING | E_RECOVERABLE_ERROR,
            'slow_ms' => 3000,
            'max_captures' => 30,
            'finish_request' => true,
            'timeout_ms' => 2000,
        ];
        $root = (string) ($this->options['root'] ?? self::guessRoot());
        if ($root !== '') {
            // Both spellings: a trace names files by their resolved path, so a
            // root reached through a symlink — a deploy's `current`, macOS's
            // `/var` — would otherwise never match.
            $real = realpath($root);
            foreach (array_unique(array_filter([$root, $real === false ? '' : $real])) as $candidate) {
                $this->roots[] = rtrim(str_replace('\\', '/', $candidate), '/') . '/';
            }
            usort($this->roots, static fn (string $a, string $b): int => strlen($b) <=> strlen($a));
        }
        $this->sessionId = 'proc-' . bin2hex(random_bytes(8));
        $this->started = (float) ($_SERVER['REQUEST_TIME_FLOAT'] ?? microtime(true));
    }

    /**
     * Reports an exception the application caught. Returns the capture id, or
     * null when it was not sent.
     *
     * @param array{feature?: string, operation?: string, severity?: string, category?: string, handled?: bool, tags?: array<string, mixed>} $options
     */
    public function captureException(\Throwable $error, array $options = []): ?string
    {
        return $this->capture(
            get_class($error),
            $error->getMessage(),
            $this->stackOf($error),
            [
                'feature' => $options['feature'] ?? $this->options['service'] ?? 'server',
                'operation' => $options['operation'] ?? 'captured',
                'severity' => $options['severity'] ?? 'moderate',
                'category' => $options['category'] ?? 'exception',
                'handled' => $options['handled'] ?? true,
                'tags' => $options['tags'] ?? [],
            ]
        );
    }

    /**
     * Reports something the application judged wrong without an exception —
     * a log line at error level. The message is sent as written: pass
     * placeholders (`Booking {id} failed`), not values, so one fault stays
     * one issue and no customer detail leaves.
     *
     * @param array{feature?: string, operation?: string, severity?: string, category?: string, tags?: array<string, mixed>} $options
     */
    public function captureMessage(string $message, array $options = []): ?string
    {
        return $this->capture('LogError', $message, '', [
            'feature' => $options['feature'] ?? $this->options['service'] ?? 'server',
            'operation' => $options['operation'] ?? 'log',
            'severity' => $options['severity'] ?? 'moderate',
            'category' => $options['category'] ?? 'log',
            'handled' => true,
            'tags' => $options['tags'] ?? [],
        ]);
    }

    /**
     * Runs a cron or queue job, reporting a failure under the job's name and
     * rethrowing it — the job's own error handling is unchanged.
     *
     * @template T
     * @param callable(): T $job
     * @return T
     */
    public function monitor(string $name, callable $job): mixed
    {
        try {
            return $job();
        } catch (\Throwable $error) {
            $this->captureException($error, ['feature' => 'job', 'operation' => $name, 'severity' => 'serious', 'handled' => false]);
            $this->flush();
            throw $error;
        }
    }

    /** Sends what is queued. For long-running workers; a web request flushes itself. */
    public function flush(): void
    {
        try {
            while ($this->queue !== []) {
                $batch = array_splice($this->queue, 0, self::MAX_BATCH);
                $this->send($batch);
            }
        } catch (\Throwable) {
            // Never into the host.
        }
    }

    /** Tests only: where batches go instead of the network. */
    public function sendWith(callable $sender): void
    {
        $this->sender = $sender;
    }

    /** Tests only. */
    public static function reset(): void
    {
        self::$instance = null;
    }

    // --------------------------------------------------------------- handlers

    private function install(): void
    {
        $this->reserve = str_repeat('x', 64 * 1024);
        $this->previousExceptionHandler = set_exception_handler(function (\Throwable $error): void {
            $this->capture(get_class($error), $error->getMessage(), $this->stackOf($error), [
                'feature' => $this->options['service'] ?? 'server',
                'operation' => 'uncaught_exception',
                'severity' => 'critical',
                'category' => 'runtime',
                'handled' => false,
                'tags' => [],
            ]);
            if ($this->previousExceptionHandler !== null) {
                ($this->previousExceptionHandler)($error);
                return;
            }
            // What PHP does with no handler: the fatal line in the error log
            // and on the page per display_errors, and a 500. Rethrowing from
            // here is not allowed, so it is said the same way.
            if (!headers_sent() && PHP_SAPI !== 'cli') {
                http_response_code(500);
            }
            $line = 'PHP Fatal error:  Uncaught ' . $error;
            if (filter_var(ini_get('log_errors'), FILTER_VALIDATE_BOOLEAN)) {
                error_log($line);
            }
            $display = (string) ini_get('display_errors');
            if ($display === 'stderr' && defined('STDERR')) {
                fwrite(STDERR, $line . PHP_EOL);
            } elseif (filter_var($display, FILTER_VALIDATE_BOOLEAN)) {
                echo PHP_EOL, $line, PHP_EOL;
            }
            if (PHP_SAPI === 'cli') {
                // PHP's exit status for an uncaught exception.
                register_shutdown_function(static function (): void {
                    exit(255);
                });
            }
        });

        $this->previousErrorHandler = set_error_handler(function (int $level, string $message, string $file = '', int $line = 0): bool {
            // `@` and error_reporting() are the application's decision.
            if ((error_reporting() & $level) !== 0 && ($level & (int) $this->options['capture_errors']) !== 0) {
                $this->capture(self::levelName($level), $message, $this->relative($file) . "($line)\n" . $this->relative((new \Exception())->getTraceAsString()), [
                    'feature' => $this->options['service'] ?? 'server',
                    'operation' => 'php_error',
                    'severity' => ($level & (E_USER_ERROR | E_RECOVERABLE_ERROR)) !== 0 ? 'serious' : 'low',
                    'category' => 'runtime',
                    'handled' => false,
                    'tags' => ['level' => self::levelName($level)],
                ]);
            }
            if ($this->previousErrorHandler !== null) {
                return (bool) ($this->previousErrorHandler)($level, $message, $file, $line);
            }
            // false: PHP's standard handler runs, so logging is unchanged.
            return false;
        });

        register_shutdown_function(function (): void {
            $this->reserve = null;
            $this->onShutdown();
        });
    }

    private function onShutdown(): void
    {
        try {
            $fatal = error_get_last();
            if ($fatal !== null && ($fatal['type'] & self::FATALS) !== 0) {
                $this->capture(self::levelName($fatal['type']), $fatal['message'], $this->relative($fatal['file']) . "({$fatal['line']})", [
                    'feature' => $this->options['service'] ?? 'server',
                    'operation' => 'fatal_error',
                    'severity' => 'critical',
                    'category' => 'runtime',
                    'handled' => false,
                    'tags' => ['level' => self::levelName($fatal['type'])],
                ]);
            }
            if (PHP_SAPI !== 'cli') {
                $status = (int) http_response_code();
                $request = $this->request();
                $where = $request['route'] ?? $request['path'] ?? '';
                if ($status >= 500 && !$this->capturedThisRequest) {
                    $this->capture('HttpError', trim(($request['method'] ?? '') . " $where answered $status"), '', [
                        'feature' => $this->options['service'] ?? 'server',
                        'operation' => 'http_5xx',
                        'severity' => 'serious',
                        'category' => 'network',
                        'handled' => false,
                        'tags' => ['status' => $status],
                    ]);
                }
                $slow = (int) $this->options['slow_ms'];
                if ($slow > 0 && (microtime(true) - $this->started) * 1000 > $slow) {
                    $this->capture('SlowRequest', trim(($request['method'] ?? '') . " $where took longer than $slow ms"), '', [
                        'feature' => $this->options['service'] ?? 'server',
                        'operation' => 'slow_request',
                        'severity' => 'low',
                        'category' => 'performance',
                        'handled' => true,
                        'tags' => ['thresholdMs' => $slow],
                    ]);
                }
            }
            if ($this->queue === []) {
                return;
            }
            // The visitor has their page; the report goes after it.
            if ($this->options['finish_request'] && function_exists('fastcgi_finish_request')) {
                fastcgi_finish_request();
            }
            $this->flush();
        } catch (\Throwable) {
            // Never into the host.
        }
    }

    // ---------------------------------------------------------------- capture

    /** @param array{feature: string, operation: string, severity: string, category: string, handled: bool, tags: array<string, mixed>} $input */
    private function capture(string $errorType, string $message, string $stack, array $input): ?string
    {
        if ($this->capturing) {
            return null;
        }
        $this->capturing = true;
        try {
            $message = Contract::scrub($message);
            $stack = Contract::scrub($stack);
            $key = Contract::fingerprint($input['feature'], $input['operation'], $errorType, $message, $stack);
            $now = microtime(true);
            $previous = $this->seen[$key] ?? null;
            if ($previous !== null && $now - $previous['at'] < self::DUPLICATE_WINDOW) {
                $this->seen[$key]['suppressed']++;
                return null;
            }
            if ($this->sentThisRequest >= (int) $this->options['max_captures']) {
                return null;
            }
            $this->sentThisRequest++;
            $this->seen[$key] = ['at' => $now, 'suppressed' => 0];
            $this->capturedThisRequest = true;

            $context = [
                'runtime' => 'php ' . PHP_VERSION,
                'sapi' => PHP_SAPI,
                'host' => (string) gethostname(),
                'pid' => getmypid(),
            ];
            if ($this->options['service'] !== null) {
                $context['service'] = $this->options['service'];
            }
            if (PHP_SAPI !== 'cli') {
                $context['request'] = $this->request();
            }
            $tags = $input['tags'];
            if (($previous['suppressed'] ?? 0) > 0) {
                $tags['suppressedSinceLastReport'] = $previous['suppressed'];
            }

            $capture = [
                'captureId' => bin2hex(random_bytes(16)),
                'occurredAt' => gmdate('Y-m-d\TH:i:s', (int) $now) . sprintf('.%03dZ', (int) (($now - floor($now)) * 1000)),
                'source' => 'php',
                'severity' => $input['severity'],
                'category' => $input['category'],
                'feature' => $input['feature'],
                'operation' => $input['operation'],
                'message' => Contract::cutUtf8($message, 4000),
                'errorType' => $errorType,
                'stackTrace' => Contract::cutUtf8($stack, 16000),
                'sessionId' => $this->sessionId,
                'handled' => $input['handled'],
                'context' => Contract::sanitize($context) ?? [],
                'tags' => Contract::sanitize($tags) ?? [],
                'breadcrumbs' => [],
            ];
            if ($this->options['release'] !== null) {
                $capture['appVersion'] = (string) $this->options['release'];
            }
            if ($this->options['environment'] !== null) {
                $capture['environment'] = (string) $this->options['environment'];
            }
            if (count($this->queue) >= self::MAX_QUEUE) {
                array_shift($this->queue);
            }
            $this->queue[] = $capture;
            return $capture['captureId'];
        } catch (\Throwable) {
            return null;
        } finally {
            $this->capturing = false;
        }
    }

    /**
     * Method, path without its query, and the route when a framework set one
     * with setRoute(). Never a header, a cookie, a parameter or a body.
     *
     * @return array<string, string|int>
     */
    private function request(): array
    {
        $request = [];
        if (isset($_SERVER['REQUEST_METHOD'])) {
            $request['method'] = strtoupper((string) $_SERVER['REQUEST_METHOD']);
        }
        if (isset($_SERVER['REQUEST_URI'])) {
            $path = parse_url((string) $_SERVER['REQUEST_URI'], PHP_URL_PATH);
            if (is_string($path)) {
                $request['path'] = Contract::cutUtf8($path, 500);
            }
        }
        if ($this->route !== null) {
            $request['route'] = $this->route;
        }
        $status = http_response_code();
        if (is_int($status)) {
            $request['status'] = $status;
        }
        $request['durationMs'] = (int) round((microtime(true) - $this->started) * 1000);
        return $request;
    }

    private ?string $route = null;

    /** The route pattern (`/bookings/{id}`) for this request, when the application knows it. */
    public function setRoute(string $route): void
    {
        $this->route = $route;
    }

    private function stackOf(\Throwable $error): string
    {
        // PHP's own trace starts at the caller of the function that threw, so
        // the throw site goes first.
        return $this->relative($error->getFile()) . '(' . $error->getLine() . ")\n" . $this->relative($error->getTraceAsString());
    }

    /** Paths under the application root, made relative: no server layout leaves, and a new deploy directory is not a new issue. */
    private function relative(string $text): string
    {
        $text = str_replace('\\', '/', $text);
        foreach ($this->roots as $root) {
            $text = str_replace($root, '', $text);
        }
        return $text;
    }

    private static function guessRoot(): string
    {
        $candidates = [];
        if (!empty($_SERVER['DOCUMENT_ROOT'])) {
            $candidates[] = dirname((string) $_SERVER['DOCUMENT_ROOT']);
        }
        $cwd = getcwd();
        if ($cwd !== false) {
            $candidates[] = $cwd;
        }
        return (string) ($candidates[0] ?? '');
    }

    private static function levelName(int $level): string
    {
        return match ($level) {
            E_ERROR => 'E_ERROR',
            E_WARNING => 'E_WARNING',
            E_PARSE => 'E_PARSE',
            E_NOTICE => 'E_NOTICE',
            E_CORE_ERROR => 'E_CORE_ERROR',
            E_CORE_WARNING => 'E_CORE_WARNING',
            E_COMPILE_ERROR => 'E_COMPILE_ERROR',
            E_COMPILE_WARNING => 'E_COMPILE_WARNING',
            E_USER_ERROR => 'E_USER_ERROR',
            E_USER_WARNING => 'E_USER_WARNING',
            E_USER_NOTICE => 'E_USER_NOTICE',
            E_RECOVERABLE_ERROR => 'E_RECOVERABLE_ERROR',
            E_DEPRECATED => 'E_DEPRECATED',
            E_USER_DEPRECATED => 'E_USER_DEPRECATED',
            default => 'E_' . $level,
        };
    }

    // -------------------------------------------------------------- transport

    /** @param list<array<string, mixed>> $batch */
    private function send(array $batch): void
    {
        $body = json_encode($batch, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE | JSON_PARTIAL_OUTPUT_ON_ERROR);
        if ($body === false) {
            return;
        }
        if ($this->sender !== null) {
            ($this->sender)($body);
            return;
        }
        $url = rtrim((string) $this->options['ingest_url'], '/') . '/v1/captures';
        $headers = [
            'Content-Type: application/json; charset=utf-8',
            'X-Citadel-Client: ' . $this->options['client_id'],
            'X-ARM-Key: ' . $this->options['ingest_key'],
            'User-Agent: citadel-arm-php/' . self::VERSION,
        ];
        $timeout = max(100, (int) $this->options['timeout_ms']);
        // One attempt: this runs as the request ends, and a retry is time the
        // host's worker is not serving anyone. A failed send is lost, which
        // is the right trade for monitoring.
        if (function_exists('curl_init')) {
            $curl = curl_init($url);
            if ($curl === false) {
                return;
            }
            curl_setopt_array($curl, [
                CURLOPT_POST => true,
                CURLOPT_POSTFIELDS => $body,
                CURLOPT_HTTPHEADER => $headers,
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_CONNECTTIMEOUT_MS => min(1000, $timeout),
                CURLOPT_TIMEOUT_MS => $timeout,
                CURLOPT_NOSIGNAL => true,
            ]);
            curl_exec($curl);
            curl_close($curl);
            return;
        }
        $context = stream_context_create(['http' => [
            'method' => 'POST',
            'header' => implode("\r\n", $headers),
            'content' => $body,
            'timeout' => $timeout / 1000,
            'ignore_errors' => true,
        ]]);
        @file_get_contents($url, false, $context);
    }
}
