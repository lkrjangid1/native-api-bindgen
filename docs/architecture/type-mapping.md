# Type mapping (Flutter / Dart over `package:jni`)

Implemented once in `packages/native_api_generator/lib/src/type_mapping.dart` (`DartJniTypeMapper`). Emitters never hard-code mappings.

| Java | Dart (strict-native, default) | JNI argument | Notes |
|---|---|---|---|
| `boolean` | `bool` | as-is | |
| `byte` | `int` | `JValueByte` | exact 8-bit width |
| `char` | `int` (UTF-16 code unit) | `JValueChar` | Dart has no char type |
| `short` | `int` | `JValueShort` | |
| `int` | `int` | `JValueInt` | |
| `long` | `int` | as-is | 64-bit |
| `float` | `double` | `JValueFloat` | |
| `double` | `double` | as-is | |
| `java.lang.String` | `JString` | as-is | `ergonomic-dart` mode: Dart `String`, converted and released at the boundary |
| generated class/interface `X` | extension type `X` (over `JObject`) | as-is | |
| type outside the closure | `JObject` | as-is | diagnostic `E016`; add it with `--entry` |
| `T[]` (primitive) | `JIntArray`, `JByteArray`, … | as-is | |
| `T[]` (reference) | `JArray<T?>` | as-is | |
| type variable `T` | erased to its first bound | as-is | diagnostic `E003` (generic generation is planned) |

Nullability: `@NonNull`/`@RecentlyNonNull` → non-nullable Dart type; `@Nullable` → `T?`; unknown → `T?`.

Constants (`static final` with `ConstantValue`) are emitted as Dart `const` with the exact SDK value (`long` max, `NaN`, unicode strings preserved).

## Naming

- Types: simple name with `$` → `_` (`Handler$Callback` → `Handler_Callback`); names that would shadow `dart:core` or built-ins get a trailing `$` (`java.lang.Object` → `Object$`).
- Members: Java names, reserved words escaped with a trailing `$` (`switch` → `switch$`); members of `Object`/`JObject` are escaped (`toString` → `toString$`, `release` → `release$`).
- Overloads: the *primary* overload (earliest API level, then fewest parameters, then simplest parameter types) keeps the plain name; others get signature suffixes (`putExtra$String$long`, `Handler.new$Looper`). The mapping is recorded in `binding_map.json` and in each member's doc comment.
