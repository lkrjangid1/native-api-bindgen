# Security Policy

Generated native bindings are security-sensitive infrastructure: they run inside applications with native privileges.

## Reporting a vulnerability

Please **do not** open a public issue. Use GitHub's private vulnerability reporting ("Report a vulnerability" on the Security tab). We aim to acknowledge reports within 7 days.

## Supported versions

Only the latest `0.x` release line receives fixes while the project is experimental.

## Hardening already in place

- Parsers (class files, zip, XML, IR JSON) are bounds-checked, size-limited and recursion-limited; malformed input produces diagnostic `E008 INVALID_AST` instead of crashing. Fuzz tests cover this.
- The generator never executes commands or code taken from SDK metadata or configuration.
- All generated files are written through a path guard that rejects absolute paths, `..` traversal and symlink escapes outside the configured output directory.
- No network access during generation. Nothing is downloaded or uploaded.
- `audit-license` / `tools/legal_scan` block committed SDK binaries.
