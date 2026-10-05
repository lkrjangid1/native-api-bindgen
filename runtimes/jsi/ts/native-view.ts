// native-api-bindgen React Native runtime: native UI layer.
// Apache License, Version 2.0.
import React from 'react';
import { requireNativeComponent, type ViewProps } from 'react-native';

type NabNativeViewProps = ViewProps & { viewId: number };

let component: React.ComponentType<NabNativeViewProps> | undefined;

interface ViewRegistry {
  registerView(h: object): number;
  unregisterView(id: number): void;
}

function registry(): ViewRegistry {
  const r = (globalThis as unknown as { __nab?: ViewRegistry }).__nab;
  if (r === undefined) {
    throw new Error('native-api-bindgen: runtime not installed (create the view through the bindings first)');
  }
  return r;
}

/** Props of {@link NativeView}. */
export interface NativeViewProps extends ViewProps {
  /** An `android.view.View` / `UIView` created through generated bindings. */
  view: { readonly $h: object };
}

/**
 * Shows a native view created through generated bindings (Android `View`,
 * iOS `UIView`) in the React tree. The view must not have another parent.
 */
export function NativeView(props: NativeViewProps): React.ReactElement {
  const { view, ...rest } = props;
  const id = React.useMemo(() => registry().registerView(view.$h), [view]);
  React.useEffect(() => () => registry().unregisterView(id), [id]);
  component ??= requireNativeComponent<NabNativeViewProps>('NabNativeView');
  return React.createElement(component, { ...rest, viewId: id });
}
