# React Native policy

> **Not legal advice.** This document describes engineering policy. Organizations should perform their own legal review before commercial redistribution.

Android support (experimental) targets the New Architecture (JSI, a pure C++ Turbo Module, Codegen) per https://reactnative.dev. React Native (MIT) is a dependency of the app, never vendored. The example app's `OnLoad.cpp` and `CMakeLists.txt` were written for this project following the documented setup rather than copied from React Native sources. Generated libraries contain only project runtime code (Apache-2.0) and SDK-derived names/descriptors (same policy as Flutter output: local-only by default). iOS is not implemented. React and React Native are trademarks of Meta Platforms, Inc.; this project is not affiliated with or endorsed by Meta.
