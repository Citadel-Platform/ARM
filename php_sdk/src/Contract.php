<?php

declare(strict_types=1);

namespace Citadel\Arm;

/**
 * ARM's document contract, ported from `arm/tooling_core` (Dart), which is
 * the reference, and held to `arm/contract/conformance.json` by
 * `tests/run.php`.
 *
 * The reference works on UTF-16 strings and PHP's are bytes, so the port does
 * three things the Dart and JavaScript ports get for free:
 *
 * - lengths and cuts are in UTF-16 code units, so a 240-unit cut through an
 *   emoji leaves half of it — a lone surrogate — exactly as Dart does;
 * - the fingerprint's JSON is written here rather than by `json_encode`,
 *   because Dart escapes only `"`, `\` and control characters, writes a lone
 *   surrogate as `\udxxx`, and leaves everything else as itself;
 * - "whitespace" is JavaScript's and Dart's set, spelled out, not PCRE's.
 *
 * The ingest computes the fingerprint that is stored. This copy only
 * recognises a repeat before it is sent.
 */
final class Contract
{
    /** ECMAScript's `\s`, which Dart's RegExp and `String.trim` also use. */
    private const WHITESPACE = '\x{0009}-\x{000D}\x{0020}\x{00A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}';

    /** Dart's `String.trim`: the same set, plus NEL (U+0085). */
    private const TRIM = self::WHITESPACE . '\x{0085}';

    public static function fingerprint(string $feature, string $operation, string $errorType, string $message, string $stack): string
    {
        $feature = self::scrub($feature);
        $operation = self::scrub($operation);
        $errorType = self::scrub($errorType);

        $parts = [
            'feature' => self::jsonString(self::utf16(mb_strtolower(self::trim($feature), 'UTF-8'))),
            'operation' => self::jsonString(self::utf16(mb_strtolower(self::trim($operation), 'UTF-8'))),
            'errorType' => self::jsonString(self::utf16(self::trim($errorType))),
            'message' => self::jsonString(self::normalizeMessage(self::scrub($message))),
        ];
        $frames = array_map(
            static fn (string $frame): string => self::jsonString(self::utf16($frame)),
            self::normalizeFrames(self::scrub($stack))
        );

        return '{"feature":' . $parts['feature']
            . ',"operation":' . $parts['operation']
            . ',"errorType":' . $parts['errorType']
            . ',"message":' . $parts['message']
            . ',"frames":[' . implode(',', $frames) . ']}';
    }

    /** `issue_` and the first 24 hex characters of the fingerprint's SHA-256. */
    public static function issueId(string $fingerprint): string
    {
        return 'issue_' . substr(hash('sha256', $fingerprint), 0, 24);
    }

    /**
     * `sanitizeArmMap`: nulls dropped at the top level only; nested arrays keep
     * their first 20 entries; strings cut at 2000 UTF-16 units; anything
     * deeper than four levels becomes Dart's text form of it.
     *
     * @param array<array-key, mixed>|null $value
     * @return array<array-key, mixed>|null
     */
    public static function sanitize(?array $value, int $maxDepth = 4, int $maxEntries = 20, int $maxStringLength = 2000): ?array
    {
        if ($value === null) {
            return null;
        }
        $result = [];
        foreach ($value as $key => $entry) {
            $safe = self::sanitizeValue($entry, 0, $maxDepth, $maxEntries, $maxStringLength);
            if ($safe !== null) {
                $result[(string) $key] = $safe;
            }
        }
        return $result;
    }

    /**
     * Makes any byte string valid UTF-8, invalid sequences replaced. A PHP
     * error message can carry raw bytes, and one invalid byte would make the
     * whole batch unencodable as JSON.
     */
    public static function scrub(string $value): string
    {
        return mb_check_encoding($value, 'UTF-8') ? $value : mb_scrub($value, 'UTF-8');
    }

    /** Cuts to at most [units] UTF-16 code units, returning valid UTF-8 (a half pair is dropped). */
    public static function cutUtf8(string $value, int $units): string
    {
        $value = self::scrub($value);
        if (strlen($value) <= $units) {
            return $value;
        }
        $utf16 = self::utf16($value);
        if (count($utf16) <= $units) {
            return $value;
        }
        $cut = array_slice($utf16, 0, $units);
        $last = end($cut);
        if ($last !== false && $last >= 0xD800 && $last <= 0xDBFF) {
            array_pop($cut);
        }
        return self::fromUtf16($cut);
    }

    // ------------------------------------------------------------ internals

    /** @return list<int> */
    private static function normalizeMessage(string $value): array
    {
        $squashed = preg_replace('/0x[0-9a-fA-F]+/', '<hex>', $value);
        // No `u` flag: `\b` and `\d` stay ASCII, as in the reference, and a
        // byte of a multi-byte character is never a word character.
        $squashed = preg_replace('/\b\d+\b/', '<n>', (string) $squashed);
        $squashed = preg_replace('/[' . self::WHITESPACE . ']+/u', ' ', (string) $squashed);
        $units = self::utf16(self::trim((string) $squashed));
        return count($units) <= 240 ? $units : array_slice($units, 0, 240);
    }

    /** @return list<string> */
    private static function normalizeFrames(string $stack): array
    {
        $frames = [];
        foreach (explode("\n", $stack) as $line) {
            $line = self::trim($line);
            if ($line === '') {
                continue;
            }
            $line = (string) preg_replace('/#[0-9]+[' . self::WHITESPACE . ']+/u', '', $line);
            $line = (string) preg_replace('/:\d+:\d+/', '', $line);
            $line = str_replace('<asynchronous suspension>', '', $line);
            $line = self::trim($line);
            if ($line === '') {
                continue;
            }
            $frames[] = $line;
            if (count($frames) === 6) {
                break;
            }
        }
        return $frames;
    }

    private static function trim(string $value): string
    {
        return (string) preg_replace('/^[' . self::TRIM . ']+|[' . self::TRIM . ']+$/u', '', $value);
    }

    /** @return list<int> UTF-16 code units. */
    private static function utf16(string $value): array
    {
        if ($value === '') {
            return [];
        }
        $bytes = mb_convert_encoding($value, 'UTF-16BE', 'UTF-8');
        return array_values(unpack('n*', $bytes) ?: []);
    }

    /** @param list<int> $units */
    private static function fromUtf16(array $units): string
    {
        if ($units === []) {
            return '';
        }
        return mb_convert_encoding(pack('n*', ...$units), 'UTF-8', 'UTF-16BE');
    }

    /**
     * Dart's `jsonEncode` of a string, from its UTF-16 code units.
     *
     * @param list<int> $units
     */
    private static function jsonString(array $units): string
    {
        $out = '"';
        $count = count($units);
        for ($i = 0; $i < $count; $i++) {
            $unit = $units[$i];
            if ($unit >= 0xD800 && $unit <= 0xDBFF && $i + 1 < $count && $units[$i + 1] >= 0xDC00 && $units[$i + 1] <= 0xDFFF) {
                $out .= mb_chr(0x10000 + (($unit - 0xD800) << 10) + ($units[$i + 1] - 0xDC00), 'UTF-8');
                $i++;
                continue;
            }
            if ($unit >= 0xD800 && $unit <= 0xDFFF) {
                $out .= sprintf('\\u%04x', $unit);
                continue;
            }
            $out .= match (true) {
                $unit === 0x22 => '\\"',
                $unit === 0x5C => '\\\\',
                $unit === 0x08 => '\\b',
                $unit === 0x09 => '\\t',
                $unit === 0x0A => '\\n',
                $unit === 0x0C => '\\f',
                $unit === 0x0D => '\\r',
                $unit < 0x20 => sprintf('\\u%04x', $unit),
                default => mb_chr($unit, 'UTF-8'),
            };
        }
        return $out . '"';
    }

    private static function sanitizeValue(mixed $value, int $depth, int $maxDepth, int $maxEntries, int $maxStringLength): mixed
    {
        if ($depth > $maxDepth) {
            return $value === null ? null : self::dartToString($value);
        }
        if ($value === null || is_int($value) || is_float($value) || is_bool($value)) {
            return $value;
        }
        if (is_string($value)) {
            return self::cutUtf8($value, $maxStringLength);
        }
        if ($value instanceof \DateTimeInterface) {
            return $value->format('Y-m-d\TH:i:s.v\Z');
        }
        if (is_array($value)) {
            $slice = array_slice($value, 0, $maxEntries, true);
            $out = [];
            foreach ($slice as $key => $entry) {
                $out[$key] = self::sanitizeValue($entry, $depth + 1, $maxDepth, $maxEntries, $maxStringLength);
            }
            return array_is_list($value) ? array_values($out) : $out;
        }
        if ($value instanceof \JsonSerializable) {
            return self::sanitizeValue($value->jsonSerialize(), $depth, $maxDepth, $maxEntries, $maxStringLength);
        }
        if (is_object($value)) {
            return self::sanitizeValue(get_object_vars($value), $depth, $maxDepth, $maxEntries, $maxStringLength);
        }
        return self::scrub((string) $value);
    }

    /** What Dart's `toString()` prints for a decoded JSON value. */
    private static function dartToString(mixed $value): string
    {
        if ($value === null) {
            return 'null';
        }
        if (is_bool($value)) {
            return $value ? 'true' : 'false';
        }
        if (is_array($value)) {
            if (array_is_list($value)) {
                return '[' . implode(', ', array_map([self::class, 'dartToString'], $value)) . ']';
            }
            $parts = [];
            foreach ($value as $key => $entry) {
                $parts[] = $key . ': ' . self::dartToString($entry);
            }
            return '{' . implode(', ', $parts) . '}';
        }
        if (is_object($value)) {
            return self::dartToString(get_object_vars($value));
        }
        return self::scrub((string) $value);
    }
}
