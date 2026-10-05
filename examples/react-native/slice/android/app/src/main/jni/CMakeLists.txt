# App native build for the native-api-bindgen React Native example.
# Follows reactnative.dev "Cross-Platform Native Modules (C++)": the default
# React Native application setup plus the generated bindings library.
cmake_minimum_required(VERSION 3.13)

project(appmodules)

include(${REACT_ANDROID_DIR}/cmake-utils/ReactNative-application.cmake)

include(${CMAKE_CURRENT_SOURCE_DIR}/../../../../../native-api-bindings/native-api-bindings.cmake)
