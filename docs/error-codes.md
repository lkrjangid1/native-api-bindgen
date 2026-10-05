# Diagnostic / error codes

Codes are stable; never renumber. Each diagnostic carries `code`, `severity` (`info|warning|error`), `symbolId` (when applicable) and `message`.

| Code | Name | Meaning | Typical action |
|---|---|---|---|
| E001 | SDK_NOT_FOUND | No SDK / platform / required file at the configured or default locations | Install the platform via SDK Manager or set `ANDROID_HOME`; `doctor` shows what was searched |
| E002 | UNSUPPORTED_TYPE | A type cannot be represented in the target language (e.g. synthetic/bridge member, unsupported construct) | Symbol is skipped with this reason |
| E003 | UNSUPPORTED_GENERIC | Generic construct erased or not representable exactly | Bound/erasure used; documented in generated doc |
| E004 | UNSUPPORTED_CALLBACK | Interface cannot be implemented from Dart (e.g. non-interface abstract class) | No `implement` factory generated |
| E005 | PRIVATE_API | Apple private API detected | Never generated |
| E006 | NON_SDK_API | Android symbol not part of the public SDK API list (hidden/non-SDK) | Never generated |
| E007 | LICENSE_REVIEW_REQUIRED | Licensing of an input/output cannot be classified confidently | Human review |
| E008 | INVALID_AST | Malformed input (class file, signature, XML, IR JSON, header) | Input skipped, generation continues |
| E009 | GENERATION_FAILURE | Emitter could not produce valid code for a symbol | Symbol skipped |
| E010 | RUNTIME_BINDING_FAILURE | Runtime could not bind (class/method not found on device) | Thrown by runtime |
| E011 | ABI_MISMATCH | Native ABI/type width mismatch | Symbol skipped |
| E012 | AVAILABILITY_MISMATCH | API newer than the device / `minApi` | Guard throws `NativeApiUnavailableException` |
| E013 | THREADING_CONSTRAINT | API annotated with a thread requirement (`@MainThread`, `@UiThread`, `@WorkerThread`) | Documented on the generated member |
| E014 | DOCUMENTATION_UNAVAILABLE | No documentation reference could be derived | Informational |
| E015 | NOT_IMPLEMENTED | Requested target/platform is not implemented in this version (no current command returns it; kept stable for future targets) | Tracked limitation (see roadmap) |
| E016 | OUTSIDE_CLOSURE | Referenced type not in the generation closure; mapped to opaque `JObject` | Add it via `--entry`/`include` |
| E017 | UNSAFE_PATH | Output path escapes the output directory | Generation aborted |
| E018 | CONFIG_INVALID | Configuration file invalid | Fix configuration |
