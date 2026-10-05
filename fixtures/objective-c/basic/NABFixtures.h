// Synthetic Objective-C fixtures written for native-api-bindgen (Apache-2.0).
// They exercise header-parser features without copying any SDK header.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NABMode) {
  NABModeOff = 0,
  NABModeOn = 1,
  NABModeAuto API_AVAILABLE(ios(15.0)) = 2,
};

typedef NS_OPTIONS(NSUInteger, NABFlags) {
  NABFlagsNone = 0,
  NABFlagsA = 1 << 0,
  NABFlagsB = 1 << 1,
  NABFlagsHigh = 1UL << 63,
};

typedef struct NABPoint {
  double x;
  double y;
} NABPoint;

typedef struct NABRect {
  NABPoint origin;
  NABPoint size;
} NABRect;

@protocol NABListener <NSObject>
- (void)thing:(id)thing didChangeValue:(NSInteger)value;
@optional
- (BOOL)shouldStop;
@end

API_AVAILABLE(ios(13.0))
@interface NABThing : NSObject <NSCopying>

@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic, readonly) NSInteger count;
@property (nonatomic) NABMode mode;
@property (nonatomic) NABRect frame;
@property (class, nonatomic, readonly) NSUInteger instances;
@property (nonatomic, weak, nullable) id<NABListener> listener;

- (instancetype)initWithName:(NSString *)name NS_DESIGNATED_INITIALIZER;
- (instancetype)init;
+ (nullable instancetype)thingWithValue:(double)value;
- (NSArray<NSString *> *)items;
- (NSDictionary<NSString *, NSNumber *> *)counts;
- (void)addItem:(NSString *)item;
- (void)addItem:(NSString *)item atIndex:(NSUInteger)index;
- (BOOL)saveToPath:(NSString *)path error:(NSError **)error;
- (void)runWithCompletion:(void (^)(BOOL ok))completion API_AVAILABLE(ios(16.0));
- (void)legacy API_DEPRECATED("Use modern", ios(13.0, 15.0));
- (NABPoint)centerOf:(NABRect)rect;
- (void)log:(NSString *)format, ...;
- (void)_privateHelper;
- (nullable id)objectForKeyedSubscript:(NSString *)key;

@end

@interface NABThing (NABExtras)
- (NSString *)describe;
@end

/// Main-actor isolated class (as UIKit declares its UI classes).
NS_SWIFT_UI_ACTOR
@interface NABMainActorView : NSObject
@property (nonatomic) double alpha;
- (void)redraw;
- (NSString *)identifier NS_SWIFT_NONISOLATED;
@end

@interface NABThing (NABMainActor)
- (void)refreshUI NS_SWIFT_UI_ACTOR;
@end

API_UNAVAILABLE(ios)
@interface NABMacOnly : NSObject
@end

NS_ASSUME_NONNULL_END
