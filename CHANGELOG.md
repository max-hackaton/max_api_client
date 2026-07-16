## [Unreleased]

## [0.1.3] - 2026-07-16

- Switched the default API endpoint to `https://platform-api2.max.ru`.
- Added the Russian Trusted Root CA to the TLS trust store, with optional `ca_file` override.
- Added an explicit `verify_ssl: false` option for environments that must temporarily ignore certificate errors.
- Documented the new endpoint and TLS configuration options.
- Updated the TypeScript reference client link.

## [0.1.2] - 2026-03-27

- Configured RubyGems trusted publishing through GitHub Actions.
- Added release tag validation and updated the Ruby CI matrix.

## [0.1.0] - 2026-02-12

- Initial release
