/// The inputs of ARM's cross-language conformance set (Feature 1.6.1).
///
/// Each case is what a client knows at capture time. The expected outputs are
/// computed by `tooling_core` — the reference implementation — and written to
/// `arm/contract/conformance.json` by `generate_conformance.dart`. Every other
/// ARM client (the browser SDK, and the PHP and Node clients when they exist)
/// must reproduce that file exactly, and `tooling_core`'s own test fails if
/// the reference drifts from what the file says.
///
/// The cases are chosen for where two languages disagree: regular-expression
/// word boundaries, whitespace classes, UTF-16 truncation, JSON escaping,
/// JavaScript and PHP stack formats, and very long messages.
final List<Map<String, Object?>> armFingerprintCases = <Map<String, Object?>>[
  <String, Object?>{
    'name': 'dart stack with async suspension',
    'feature': 'Checkout',
    'operation': ' submit_payment ',
    'errorType': 'StateError',
    'message': 'Payment failed for order 9817 at pointer 0xAABBCCDD',
    'stack':
        '#0      submitPayment (package:citadel/app.dart:10:2)\n'
        '#1      <asynchronous suspension>\n'
        '#2      checkout (package:citadel/checkout.dart:30:8)\n',
  },
  <String, Object?>{
    'name': 'chrome stack',
    'feature': 'booking',
    'operation': 'load_slots',
    'errorType': 'TypeError',
    'message': "Cannot read properties of undefined (reading 'slots')",
    'stack':
        "TypeError: Cannot read properties of undefined (reading 'slots')\n"
        '    at renderSlots (https://book.client.example/_next/static/chunks/app/page-3f9a1c.js:1:20488)\n'
        '    at Array.map (<anonymous>)\n'
        '    at BookingPage (https://book.client.example/_next/static/chunks/app/page-3f9a1c.js:1:21002)\n'
        '    at async loadSlots (https://book.client.example/_next/static/chunks/app/page-3f9a1c.js:1:19877)',
  },
  <String, Object?>{
    'name': 'firefox and safari stack',
    'feature': 'booking',
    'operation': 'load_slots',
    'errorType': 'TypeError',
    'message': 'data is undefined',
    'stack':
        'renderSlots@https://book.client.example/app.js:14:9\n'
        'BookingPage@https://book.client.example/app.js:40:3\n'
        '@https://book.client.example/app.js:88:1\n',
  },
  <String, Object?>{
    'name': 'php 8 trace',
    'feature': 'bookings',
    'operation': 'confirm',
    'errorType': r'PDOException',
    'message': 'SQLSTATE[HY000] [2002] Connection refused',
    'stack':
        r'#0 /var/www/html/src/Db.php(42): PDO->__construct()' '\n'
        r'#1 /var/www/html/src/Booking.php(118): App\Db::connect()' '\n'
        r'#2 /var/www/html/public/index.php(12): App\Booking->confirm(Array)' '\n'
        '#3 {main}',
  },
  <String, Object?>{
    'name': 'digits inside words are kept, standalone numbers are not',
    'feature': 'orders',
    'operation': 'v2_sync',
    'errorType': 'HttpError',
    'message': 'v2 endpoint /api/v2/orders/12345 answered 503 after 3 tries (utf8, sha256)',
    'stack': '',
  },
  <String, Object?>{
    'name': 'tabs, newlines and non-breaking spaces collapse',
    'feature': 'forms',
    'operation': 'send',
    'errorType': 'Error',
    'message': 'mail\tfailed\n\nfor  form  12',
    'stack': '   \n\n',
  },
  <String, Object?>{
    'name': 'non-ascii and characters JSON escapes',
    'feature': '预约',
    'operation': 'créer',
    'errorType': 'Error',
    'message': 'Échec "réservation" — 客户 \\ 😀 control\u0001char',
    'stack': 'at 预约 (https://x.example/a.js:1:1)',
  },
  <String, Object?>{
    'name': 'message longer than 240 characters is cut at 240 UTF-16 units',
    'feature': 'reports',
    'operation': 'export',
    'errorType': 'RangeError',
    'message': 'x' * 239 + '😀' + 'tail that is cut off',
    'stack': 'a\nb\nc\nd\ne\nf\ng\nh',
  },
];

/// Values sanitised before storage, and what the reference makes of them.
final List<Map<String, Object?>> armSanitizerCases = <Map<String, Object?>>[
  <String, Object?>{
    'name': 'nesting deeper than four levels becomes a string',
    'input': <String, Object?>{
      'a': <String, Object?>{
        'b': <String, Object?>{
          'c': <String, Object?>{
            'd': <String, Object?>{
              'e': <String, Object?>{'f': 1},
            },
          },
        },
      },
    },
  },
  <String, Object?>{
    'name': 'a map or list past the depth limit becomes Dart\'s own text form',
    'input': <String, Object?>{
      'a': <String, Object?>{
        'b': <String, Object?>{
          'c': <String, Object?>{
            'd': <String, Object?>{
              'e': <String, Object?>{
                'map': <String, Object?>{'k': 'v', 'n': 2, 'b': true},
                'list': <Object?>['x', 3, null],
              },
            },
          },
        },
      },
    },
  },
  <String, Object?>{
    'name': 'lists and maps keep their first twenty entries',
    'input': <String, Object?>{
      'list': <int>[for (var i = 0; i < 25; i += 1) i],
    },
  },
  <String, Object?>{
    'name': 'long strings are cut at 2000 UTF-16 units',
    'input': <String, Object?>{'s': 'y' * 2100},
  },
  <String, Object?>{
    'name': 'null values are dropped at the top level only',
    'input': <String, Object?>{
      'kept': 'v',
      'dropped': null,
      'inner': <String, Object?>{'nullKept': null},
    },
  },
];
