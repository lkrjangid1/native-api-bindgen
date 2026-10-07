# React Native policy

<!-- description: Policy for React Native: New Architecture via documented Turbo Module setup, no vendored React Native sources, and local-only generated libraries. -->

> **Not legal advice.** This document describes engineering policy. Organizations should perform their own legal review before commercial redistribution.

Android support (experimental) targets the New Architecture (JSI, a pure C++ Turbo Module, Codegen) per https://reactnative.dev. React Native (MIT) is a dependency of the app, never vendored. The example app's `OnLoad.cpp` and `CMakeLists.txt` were written for this project following the documented setup rather than copied from React Native sources. Generated libraries contain only project runtime code (Apache-2.0) and SDK-derived names/descriptors/selectors (same policy as Flutter output: local-only by default). On iOS (experimental) the Turbo Module is registered through the documented `codegenConfig.ios.modulesProvider` mechanism and the generated podspec links only the frameworks the developer configured; Apple SDK policy (`docs/legal/apple.md`) applies to the iOS half. React and React Native are trademarks of Meta Platforms, Inc.; this project is not affiliated with or endorsed by Meta.
