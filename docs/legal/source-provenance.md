# Source provenance

> **Not legal advice.** This document describes engineering policy. Organizations should perform their own legal review before commercial redistribution.

## What is generated, from where

| Generated content | Derived from | Where it is recorded |
|---|---|---|
| Class/method/field names, JVM descriptors, modifiers, inheritance | `android.jar` class files (local) | IR `provenance.sourceKind = sdk`, `localArtifact = android.jar`, `sdkVersion` |
| Constant values (`static final` primitives/strings) | `ConstantValue` attributes in `android.jar` | same |
| Availability (introduced/deprecated/removed) | `data/api-versions.xml` (local) | IR `availability`, provenance `api-versions` |
| Nullability, threading, permissions, IntDef | class-file annotations; `data/annotations.zip` (local) | IR `annotations[].source` |
| Documentation | **Not copied.** Generated comments contain metadata plus a link to the official reference page | `officialReference` |

## Locally consumed, never redistributed
SDK jars, XML metadata, annotation archives, Apple headers/frameworks.

## Redistributed by this repository
Only project-authored source code, synthetic test fixtures written for this project, and project documentation.

## Generated bindings
Generated bindings are written to the user's project. Default `distribution.generatedArtifacts: local-only` keeps them out of published packages (`audit-license` warns if a package marked for publishing contains them). Whether a particular set of generated bindings may be published is `LEGAL_REVIEW_REQUIRED`.

## Private / hidden API policy
Android symbols absent from the public API list are classified `hidden_or_non_sdk` (E006) and are never emitted. Apple private APIs (E005) will be treated the same way. The project never documents techniques to bypass platform restrictions.
