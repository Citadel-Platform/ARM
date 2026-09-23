# ARM conformance set

`conformance.json` is what every ARM client must reproduce: the fingerprint
and issue id for a set of captures, and the sanitised form of a set of values.
Feature 1.6.1.

- **Generated, never edited.** `arm/tooling_core` is the reference;
  `dart run tool/generate_conformance.dart` from that package writes the file,
  and its test fails if the reference and the file disagree.
- **Reproduced by every other client.** `arm/web_sdk`'s test holds the
  browser port to it. The PHP and Node clients (Feature 1.6.3) will do the
  same when they exist.

The cases are picked for where languages disagree — regex word boundaries,
whitespace classes, cutting a string through a surrogate pair, JSON escaping,
Dart's text form of a map — and for the stack formats of Dart, V8,
Firefox/Safari and PHP.

**What the shared algorithm does not do, and a browser client must.** A V8
stack's first line repeats the error message verbatim, so the digit
normalisation applied to `message` is bypassed there; and bundlers put a
content hash in chunk names (`page-3f9a1c.js`) that changes every deploy. Both
would split one fault into many issues. They are the browser client's
pre-processing (Feature 1.6.2), not a change to this contract.
