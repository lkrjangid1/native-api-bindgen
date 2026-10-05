# Native IR

Package: `packages/native_api_ir`. Schema version: **1** (`irSchemaVersion`).

The IR is the only contract between parsers and generators. It is platform-neutral (Android today, Apple next), serializes to canonical JSON (sorted keys, sorted members, no timestamps) and round-trips losslessly.

## Nodes

| Node | Key fields |
|---|---|
| `ApiModule` | `platform`, `sdkVersion`, `sourceRevision`, `generatorVersion`, `types[]`, `diagnostics[]` |
| `ApiType` | `id`, `name`, `kind` (class, interface, enum, annotation, record, struct, protocol), `namespace`, `typeParameters`, `superClass`, `interfaces`, `enclosingType`, `nestedTypes`, `fields`, `methods`, `properties`, `threading`, `provenance` |
| `ApiMethod` | `kind` (constructor/method), `returnType`, `parameters` (name + `nameSource`), `typeParameters`, `throws`, `threading`, `permissions`, `asyncKind`, `nativeDescriptor` |
| `ApiField` | `type`, `constantValue` (typed exact literal), `nativeDescriptor` |
| `ApiProperty` | derived getter/setter pairs (`read-only`/`read-write`, `accessor`/`field` backing) — modelled, not yet populated |

Every node also carries: `modifiers`, `annotations` (raw values + classification + source), `availability` (`introduced`/`deprecated`/`removed` as `major[.minor]` versions, raw SDK-extension info), `visibility` (`public`, `hiddenOrNonSdk`, `private`), `support` (`supported`, `partial`, `unsupported`), `documentation` (link only by default) and `diagnostics` (stable codes).

## Types

`TypeRef` is sealed: `PrimitiveTypeRef`, `DeclaredTypeRef` (binary name + type arguments), `TypeVariableRef`, `WildcardTypeRef`, `ArrayTypeRef`. Every reference type carries `nullability` (`nonnull`, `nullable`, `unknown` — generators treat unknown as nullable).

## Symbol IDs

Deterministic and independent of generated file names:

```
android.content.Intent                         type
android.os.Handler$Callback                    nested type (binary name)
android.content.Intent#setData(android.net.Uri) method (erased parameter types)
android.content.Intent#<init>(java.lang.String) constructor
android.content.Intent#ACTION_VIEW              field
```

## Invariants (`validateModule`)

- IDs are unique; member IDs are prefixed by their owner.
- Non-public symbols are never `supported`.
- Every `unsupported` symbol has at least one reason diagnostic (no silent drops).

## Target annotation

Each generator first runs a *planner* that copies the module and records target-specific decisions (e.g. `E002` protected member, `E003` generic erasure, `E016` outside closure). Coverage, `why-generated` and `why-skipped` read this annotated IR (`.native_api_bindgen/ir.json`), so reports can never disagree with the generated code.
