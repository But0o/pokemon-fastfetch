# Changelog

## [2.1.0] - 2026-08-01

### Added

- Shared Bash utility library at `lib/common.sh`.
- Centralized user configuration.
- Configurable Pokémon panel dimensions.
- Optional system-information panel.
- Optional terminal color palette.
- Bundled offline Pokédex installation.
- Automated test suite.
- GitHub Actions continuous integration.
- ShellCheck configuration.
- EditorConfig configuration.
- Isolated installation tests.
- Validation for required files, directories, executables, commands, and JSON files.
- Version loading through the central `VERSION` file.

### Changed

- Refactored the installer to use shared validation and message functions.
- Reworked the migration script to delegate installation to `install.sh`.
- Updated managed paths while preserving user visual preferences.
- Installed `uninstall.sh`, `VERSION`, and `lib/common.sh` with the application.
- Standardized status, warning, success, and error messages.
- Improved installation, migration, and post-installation validation.
- Expanded project documentation and troubleshooting guidance.
- Updated the repository structure for easier maintenance.
- Improved XDG directory support.

### Fixed

- Fixed fresh installations not copying `config/pokedex.json`.
- Fixed migrated installations missing `lib/common.sh`.
- Fixed outdated paths remaining after reinstallations.
- Fixed missing installed copies of `uninstall.sh` and `VERSION`.
- Fixed unsafe validation functions under `set -u`.
- Fixed duplicated and obsolete Fish startup references.
- Fixed inconsistent version strings across scripts.
- Fixed multiple ShellCheck warnings and false-positive handling.

### Internal

- All Bash scripts pass `bash -n`.
- All maintained Bash scripts pass ShellCheck.
- Tests validate repository files, the Pokédex, the shared library, help commands, and isolated installation.
- CI validates syntax, ShellCheck, Pokédex integrity, and the automated test suite.

## 2.0.0

- Nuevo panel horizontal de Pokémon.
- Estadísticas base almacenadas localmente.
- Habilidades, región, generación, altura y peso.
- Paneles renderizados con caché persistente.
- Ejecución sin solicitudes a PokeAPI en tiempo de ejecución.
- Selección aleatoria, por nombre o por número.
- Compatibilidad con distintas ubicaciones de pokimg.
- Preparación para actualización desde la versión 1.
