// native-api-bindgen React Native runtime: native UI layer.
// Licensed under the Apache License, Version 2.0 (project source).
#import <React/RCTViewManager.h>
#import <UIKit/UIKit.h>

// Provided by NabObjCRuntime.mm (views registered from JavaScript).
extern "C" UIView* NabViewForId(NSInteger viewId);

/// `<NativeView>`: a container showing a UIView created through generated
/// bindings. Served to the New Architecture by the legacy interop layer.
@interface NabNativeViewManager : RCTViewManager
@end

@implementation NabNativeViewManager

RCT_EXPORT_MODULE(NabNativeView)

- (UIView*)view {
  return [UIView new];
}

RCT_CUSTOM_VIEW_PROPERTY(viewId, NSInteger, UIView) {
  for (UIView* sub in [view.subviews copy]) [sub removeFromSuperview];
  UIView* hosted = NabViewForId(json == nil ? 0 : [json integerValue]);
  if (hosted == nil) return;
  [hosted removeFromSuperview];
  hosted.frame = view.bounds;
  hosted.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [view addSubview:hosted];
}

@end
