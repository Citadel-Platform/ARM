# Citadel ARM Console Notes

## Scope
This Flutter web app is the ARM triage console for Citadel Platform.

## Design direction
- Follow a Google Cloud Platform-style console pattern with Material 3 components.
- Keep dashboard, form, report, and table layouts simple, readable, and scalable.
- Support both mobile and desktop web browsers.
- Preserve the existing ARM Console implementation unless a Citadel integration task explicitly changes it.

## Data posture
- The console may maintain its own project registry and role metadata.
- Monitored project ARM evidence should remain read-only by default.
- Do not copy secrets or Firebase credentials into tracked files.
