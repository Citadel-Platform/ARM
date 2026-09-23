# citadel/arm-php

ARM for PHP 8.1+ (Feature 1.6.3). Captures uncaught exceptions, fatal errors
(memory exhaustion and timeouts included), warnings, 5xx answers and slow
requests, and sends them to Citadel's shared ARM ingest with the client id
and ARM ingest key. The ingest groups them and writes the client's own
`citadel-arm`; this package never touches Firestore.

## Install

Without Composer — most custom PHP apps: download
`https://<arm-ingest>/sdk/v1/arm-php.zip`, unzip it beside the app, and at the
top of the front controller (or in `auto_prepend_file`):

```php
require __DIR__ . '/citadel-arm/autoload.php';
\Citadel\Arm\Arm::init([
    'client_id'   => 'CLIENT_ID',        // ARM → Set up ARM → Issue the ingest key
    'ingest_key'  => 'ARM_INGEST_KEY',
    'ingest_url'  => 'https://<arm-ingest>',
    'release'     => '2026.09.23',       // optional
    'environment' => 'production',       // optional
    'service'     => 'bookings',         // optional: what this app is
]);
```

With Composer: add the unzipped directory as a `path` repository and
`composer require citadel/arm-php`.

Then, optionally:

- `Arm::instance()->setRoute('/bookings/{id}')` — group by route, not path.
- `Arm::instance()->monitor('nightly-invoices', fn () => ...)` — a cron or
  queue job, reported under its name and rethrown.
- `new \Citadel\Arm\ArmLogger(Arm::instance(), $monolog)` — PSR-3; reports
  error-level entries and passes everything on. Needs `psr/log`.
- `new \Citadel\Arm\ArmMiddleware(Arm::instance())` — PSR-15. Needs
  `psr/http-server-middleware`.

## What it will not do

- **Change what PHP does with an error.** The log line, the page output per
  `display_errors`, the 500 and the CLI exit status 255 are as they were; an
  application's own exception or error handler still runs; `@` and
  `error_reporting()` are respected.
- **Keep the visitor waiting.** Captures are sent once, at the end of the
  request, one attempt with a 2-second ceiling; under PHP-FPM the response is
  finished first (`finish_request`, default on). Notices and deprecations are
  not captured (`capture_errors`).
- **Send a header, cookie, parameter or body.** A request contributes its
  method, path without query, route when set, status and duration. Paths
  under the app root are sent relative to it, symlinked deploy directories
  included; messages are made valid UTF-8 before sending.

## Development

`php tests/run.php` — the contract against `arm/contract/conformance.json`,
and the client in real processes: a `php -S` stands in for the ingest, and CLI
scripts and a web app fail against it. `node tool/build_zip.mjs <out.zip>` —
the no-Composer download.
