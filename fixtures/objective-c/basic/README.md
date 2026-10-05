# Synthetic Objective-C fixtures

`NABFixtures.h` is hand-written for this project (Apache-2.0) and is **not** derived from any Apple SDK header. It exercises: classes, protocols (required/optional), categories, properties (class, readonly, weak, struct-typed), designated initializers, nullability (`NS_ASSUME_NONNULL`, `nullable`), generics (`NSArray<NSString *>`), `NS_ENUM`/`NS_OPTIONS` (including a 64-bit unsigned value), structs (nested), blocks, `NSError **` out-parameters, variadic methods, private (`_`-prefixed) selectors, availability (`API_AVAILABLE`, `API_DEPRECATED`, `API_UNAVAILABLE`).

Tests parse it against the installed iOS simulator SDK (macOS + Xcode only); Foundation itself is read from the local SDK and never copied.
