// native-api-bindgen React Native runtime (JSI <-> Objective-C): blocks.
// Licensed under the Apache License, Version 2.0 (project source).
// Objective-C++ only (included by the runtime and the generated block
// factories, never by plain C++ translation units).
#pragma once

#import <Foundation/Foundation.h>

#include <memory>
#include <string>
#include <vector>

#include "NabObjCRuntime.h"

namespace nab::objc {

/// A JavaScript function wrapped as an Objective-C block. Owned by the block
/// (shared_ptr captured by it); the JS function is released on the JS thread.
struct BlockTarget;

/// Creates a block of one native signature that forwards to [target].
using BlockMaker = id (*)(std::shared_ptr<BlockTarget> target);

/// One generated block signature: [key] is referenced by `B<key>;`
/// conversion codes, [codes] are the JS codes of the result and arguments
/// (`v`, `z`, `n`, `j`, `s`, `o`).
struct BlockFactory {
  const char* key;
  const char* codes;
  BlockMaker make;
};

/// Called by generated blocks with boxed arguments (NSNumber for scalars,
/// objects as-is, nil allowed). On the JS thread the function runs
/// synchronously and its boxed result is returned; elsewhere a `void`
/// block's call is posted to the JS thread (arguments stay retained until
/// then) and nil is returned. Non-void blocks invoked off the JS thread
/// cannot wait for JavaScript: they log and return nil / 0.
id callBlock(const std::shared_ptr<BlockTarget>& target, std::vector<id> args);

} // namespace nab::objc
