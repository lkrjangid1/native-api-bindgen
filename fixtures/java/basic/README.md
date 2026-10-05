# Synthetic Java fixtures

Hand-written for this project (Apache-2.0). They exercise parser and generator
features without depending on any platform SDK (TRD §65):
generics, nullability, overloads, callbacks, enums, nested types, annotations,
deprecation, API levels, exceptions, async callbacks, reserved words, and a
simulated non-SDK class.

`src/androidx/annotation/*` are minimal *test stubs* that only reproduce
annotation names so recognition rules can be exercised; they are not copies of
AndroidX sources.

`api-versions.xml` is a synthetic availability list used only for
`ApiLevelClass` / `AnnotatedClass` / hidden-API tests.

Tests compile these with `javac --release 17` into a temporary directory; no
class files are committed.
