# mediaremote-adapter (vendored)

- Upstream: https://github.com/ungive/mediaremote-adapter
- Commit: 0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd (2026-10-17)
- License: BSD 3-Clause, see [LICENSE](LICENSE). Copyright (c) 2025 Jonas van den Berg and contributors.

Only the Perl script (`bin/`), the public header (`include/`) and the Objective-C sources (`src/`) are kept.
`scripts/build-adapter.sh` compiles them into `MediaRemoteAdapter.framework` with clang (no CMake needed).
The framework is bundled inside the app and loaded by `/usr/bin/perl`; the app never links against it.
Files here are unmodified.
