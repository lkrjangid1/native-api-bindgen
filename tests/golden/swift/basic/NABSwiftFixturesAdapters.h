// GENERATED CODE - DO NOT MODIFY BY HAND.
// Objective-C view of the @objc adapters for `NABSwiftFixtures` (binding input; not compiled).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class NABSwiftFixtures_Counter;
@class NABSwiftFixtures_Temperature;
@class NABSwiftFixtures_Level;
@class NABSwiftFixtures_Mood;

/// Adapter for the Swift type `NABSwiftFixtures.Counter`.
@interface NABSwiftFixtures_Counter : NSObject
@property (nonatomic, readonly) NSInteger value;
@property (nonatomic, strong) NSString *label;
- (instancetype)initWithStart:(NSInteger)start label:(NSString *)label;
- (NSInteger)incrementBy:(NSInteger)step;
- (NSString *)describePrefix:(NSString * _Nullable)prefix;
- (NABSwiftFixtures_Temperature *)temperature;
- (BOOL)isAbove:(NABSwiftFixtures_Temperature *)threshold;
+ (NABSwiftFixtures_Counter *)make;
@property (class, nonatomic, readonly) NSInteger instances;
- (void)laterWithCompletion:(void (^)(NSInteger))completion;
- (NSArray<NSNumber *> *)values;
- (NSDictionary<NSString *, NSNumber *> *)tags;
- (NSArray<NABSwiftFixtures_Counter *> *)neighbors;
- (NSString *)names:(NSArray<NSString *> *)list;
- (BOOL)checkLimit:(NSInteger)limit error:(NSError **)error;
- (NABSwiftFixtures_Counter * _Nullable)duplicateNamed:(NSString *)name error:(NSError **)error;
- (nullable instancetype)initWithValidating:(NSInteger)start error:(NSError **)error;
- (void)waitWithCompletion:(void (^)(void))completion;
- (void)fetchId:(NSInteger)id completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion;
+ (void)totalOf:(NSArray<NABSwiftFixtures_Counter *> *)counters completion:(void (^)(NSInteger))completion;
@property (nonatomic, strong) NSString *mood;
- (NSInteger)level;
- (NSString *)describeLevel:(NSInteger)level;
@end

/// Raw values of the cases of the Swift enum `NABSwiftFixtures.Level`.
@interface NABSwiftFixtures_Level : NSObject
@property (class, nonatomic, readonly) NSInteger low;
@property (class, nonatomic, readonly) NSInteger high;
@end

/// Raw values of the cases of the Swift enum `NABSwiftFixtures.Mood`.
@interface NABSwiftFixtures_Mood : NSObject
@property (class, nonatomic, readonly) NSString *happy;
@property (class, nonatomic, readonly) NSString *sad;
@end

/// Adapter for the Swift type `NABSwiftFixtures.Temperature`.
@interface NABSwiftFixtures_Temperature : NSObject
@property (nonatomic) double celsius;
- (instancetype)initWithCelsius:(double)celsius;
@property (nonatomic, readonly) double fahrenheit;
- (NABSwiftFixtures_Temperature *)adding:(double)delta;
- (void)reset;
@end

NS_ASSUME_NONNULL_END
