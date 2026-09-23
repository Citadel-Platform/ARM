Real OTLP/HTTP exports, recorded 23/09/26 from the official OpenTelemetry JS
SDK (sdk-trace-base 2.11.0, sdk-logs 0.222.0, the `-otlp-proto` and
`-otlp-http` exporters), one file per request, `.pb` protobuf and `.json`
JSON:

- `traces-1` — a span with a recorded exception and ERROR status
- `traces-2` — a healthy span
- `traces-3` — an ERROR span with no exception event
- `logs-1` — INFO; `logs-2` — ERROR; `logs-3` — FATAL with exception attributes

Recorded rather than written by hand, so the decoder is tested against what an
exporter actually sends.
