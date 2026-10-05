// native-api-bindgen React Native runtime. Apache License, Version 2.0.
// Codegen spec for the single C++ Turbo Module that installs `global.__nab`.
import type {TurboModule} from 'react-native';
import {TurboModuleRegistry} from 'react-native';

export interface Spec extends TurboModule {
  readonly install: () => boolean;
}

export default TurboModuleRegistry.getEnforcing<Spec>('NativeApiBindgen');
