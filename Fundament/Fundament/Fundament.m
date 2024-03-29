//
//  Fundament.m
//  Fundament
//
//  Created by Jon Packer on 29/11/11.
//

#import "Fundament.h"
#import "JSONKit.h"
#import "ASIHTTPRequest.h"

#pragma mark - Logging

/**
 * Defines whether to show debug logging for Fundament. Likely for my own development purposes only, really.
 * 0 = Off
 * 1 = Errors
 * 2 = Info
 */
#define FundamentLogLevel 2

static inline void FundamentLog(UInt8 level, NSString* format, ...) {
#if FundamentLogLevel > 0
  if (level > FundamentLogLevel) return;
  
  va_list args;
  va_start(args, format);
  NSLogv([NSString stringWithFormat:@"Fundament: %@", format], args); // There's probably a better way to do this...
  va_end(args);
#endif 
}

#pragma mark - Info Keys

#define FundamentDataSourceKey @"dataSource"
#define FundamentListenersKey @"listeners"
#define FundamentStatusKey @"status"
#define FundamentKeyKey @"key"

#pragma mark - Internal Typedefs

typedef id (^FundamentParserBlock)(ASIHTTPRequest*);

#pragma mark - UUID Generation

static NSString* FundamentCreateUUID() {
  CFUUIDRef uuidRef = CFUUIDCreate(kCFAllocatorDefault);
  NSString *uuidStr = [(NSString *)CFUUIDCreateString(kCFAllocatorDefault, uuidRef) autorelease];
  CFRelease(uuidRef);
  
  return uuidStr;
}

#pragma mark - Internal Listener Class Base

// This is the base listener class that allows us the store listeners in an abstract way inside a dictionary quite
// easily. 
@interface FundamentListener : NSObject 

- (void) callWithData:(id)data; // Call this listener.

@end

#pragma mark Internal Listener - Block

@interface FundamentBlockListener : FundamentListener  

@property (nonatomic, copy) FundamentCallback block;

- (id) initWithBlock:(FundamentCallback)block;

@end

#pragma mark Internal Listener - Target & Sel

@interface FundamentTargetSelListener : FundamentListener 

@property (nonatomic, assign) id target;
@property (nonatomic, assign) SEL selector;

- (id) initWithTarget:(id)target selector:(SEL)sel;

@end

#pragma mark - Parsers

#define FundamentParserJSON ^(ASIHTTPRequest* request) { return [request.responseData objectFromJSONData]; }
#define FundamentParserString ^(ASIHTTPRequest* request) { return request.responseString; }
#define FundamentParserData ^(ASIHTTPRequest* request) { return request.responseData; }
#define FundamentParserPlist ^(ASIHTTPRequest* request) { NSError* error; \
  return [NSPropertyListSerialization propertyListWithData:request.responseData \
                                                   options:NSPropertyListImmutable format:NULL error:&error]; }
#define FundamentParserImage ^(ASIHTTPRequest* request) { return [UIImage imageWithData:request.responseData]; }

#pragma mark - Private Methods

@interface Fundament( PrivateMethods )

/**
 * Adds the instance as a listener to the application notifications that we're interested in - these are
 * - UIApplicationWillEnterForeground 
 * - UIApplicationDidEnterBackground
 */
- (void) createNotificationObservers;

// Will load data sources from the default config file.
- (id) initAsShared;

// Adds a timer to the collection, and optionally executes it immediately.
- (void) addTimer:(NSTimer *)timer forKey:(NSString *)key andExecuteImmediately:(BOOL)executeImmediately;

// Creates a timer
- (NSTimer *) timerForDataSource:(FundamentDataSourceBlock)dataSource forKey:(NSString *)key 
              withUpdateInterval:(NSTimeInterval)updateInterval;

- (void) addWebDataSource:(NSURL *)dataSource withParserBlock:(FundamentParserBlock)parser 
            updateInterval:(NSTimeInterval)updateInterval forKey:(NSString *)key;

// Called when a timer fires, delegates the call off to where it should go.
- (void) timerFired:(NSTimer *)timer;

// Refreshes the data source contained in the given info.
- (void) refreshDataSourceWithInfo:(NSMutableDictionary *)info;

// Return the info for a certain data source's key
- (NSMutableDictionary *) infoForDataSourceWithKey:(NSString *)key;

// Return that status for a certain data source
- (FundamentTimerStatus) statusForDataSourceWithKey:(NSString *)key;

// Allows dry runs of observer removal. If the object is found, and dryRun = YES, it is not removed and YES is returned.
// otherwise NO is returned.
- (BOOL) removeObserver:(NSString *)observerId dryRun:(BOOL)dryRun;

// Get a mutable array of listeners for the given key
- (NSMutableDictionary *) observersForKey:(NSString *)key;

// Master listener adder
- (NSString *) addObserverForKey:(NSString *)key 
           withFundamentListener:(FundamentListener *)listener 
                      observerId:(NSString *)observerId 
                 withNamespacing:(BOOL)namespacing 
                     overwriting:(BOOL)overwriting;


// Invalidate all timers
- (void) invalidateTimers;

// Revalidate all timers
- (void) revalidateTimers;

// Create a timer
- (NSTimer *) timerWithUpdateInterval:(NSTimeInterval)updateInterval userInfo:(NSDictionary *)userInfo;

// Return true if the timer is beyond it's fire-by date.
- (BOOL) timerShouldFire:(NSTimer *)timer;

@end

@implementation Fundament

#pragma mark - Class Methods & Static Stuff

static Fundament* sharedFundament = nil;

+ (void) initialize {
  [self sharedFundament];
}

+ (Fundament *) sharedFundament {
  return sharedFundament ? sharedFundament : (sharedFundament = [[Fundament alloc] initAsShared]);
}

#pragma mark - Property Synthesis

#pragma mark - Object Lifecycle

- (id) init {
  if ( !(self = [super init]) ) {
    return nil;
  }
  
  [self createNotificationObservers];
  
  _timers         = [[NSMutableDictionary alloc] init],
  _dataCache      = [[NSCache alloc] init];
  
  return self;
}

- (id) initAsShared {
  if ( !(self = [self init]) ) {
    return nil;
  }
  
  // TODO  ---  load json defaults
  
  return self;
}

- (void) dealloc {
  [_timers release],        _timers = nil;
  [_dataCache release],     _dataCache = nil;
  
  [super dealloc];
}

#pragma mark - Application Observers

- (void) createNotificationObservers {
  NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
  
  [center addObserver:self selector:@selector(applicationWillEnterForeground:) 
                 name:UIApplicationWillEnterForegroundNotification object:nil];
  [center addObserver:self selector:@selector(applicationDidEnterBackground:) 
                 name:UIApplicationDidEnterBackgroundNotification object:nil];
  
  FundamentLog(2, @"Created application state notification observers");
}

- (void) applicationWillEnterForeground:(NSNotification *)notification {
  FundamentLog(2, @"Application Will Enter Foreground");
  
  [self revalidateTimers];
}

- (void) applicationDidEnterBackground:(NSNotification *)notification {
  FundamentLog(2, @"Application Did Enter Background");
  
  [self invalidateTimers];
}

#pragma mark - Timers

- (void) hibernateTimerWithKey:(NSString *)key {
  NSTimer* timer = [_timers objectForKey:key];
  
  NSMutableDictionary* hibernationData = [NSMutableDictionary dictionaryWithCapacity:3];
  
  [hibernationData setObject:[NSNumber numberWithDouble:timer.timeInterval] forKey:@"timeInterval"];
  [hibernationData setObject:timer.userInfo forKey:@"userInfo"];
  
  [timer invalidate];
  [hibernationData setObject:timer.fireDate forKey:@"fireDate"];
  
  FundamentLog(2, @"Hibernated with most recent fireDate: %@", timer.fireDate);
  
  [timer invalidate];
  
  [_timers setObject:hibernationData forKey:key];
}

- (void) awakeTimerWithKeyFromHibernation:(NSString *)key {
  NSDictionary* hibernatingTimer = [_timers objectForKey:key];
  
  if (![hibernatingTimer isKindOfClass:[NSDictionary class]]) { // not hibernating or something's wrong
    return;
  }
  
  NSDate* fireDate = [hibernatingTimer objectForKey:@"fireDate"];
  NSTimeInterval timeInterval = [[hibernatingTimer objectForKey:@"timeInterval"] doubleValue];
  NSDictionary* userInfo = [hibernatingTimer objectForKey:@"userInfo"];
  
  // This is broken - fireDate does not work as I am expecting.
  // BOOL shouldFire = -[fireDate timeIntervalSinceNow] > timeInterval;
  
  NSTimer* awokenTimer = [self timerWithUpdateInterval:timeInterval userInfo:userInfo];
  [_timers setObject:awokenTimer forKey:key];
  
  //if (shouldFire) {
    [awokenTimer fire];
  //}
}

- (void) invalidateTimers {
  for (NSString* key in _timers.allKeys) {
    [self hibernateTimerWithKey:key];
  }
}

- (void) revalidateTimers {
  for (NSString* key in _timers.allKeys) {
    [self awakeTimerWithKeyFromHibernation:key];
  }
}

- (BOOL) timerShouldFire:(NSTimer *)timer {
  return -[timer.fireDate timeIntervalSinceNow] > timer.timeInterval;
}

- (NSTimeInterval) defaultUpdateInterval {
  return _defaultUpdateInterval > 0 ? _defaultUpdateInterval : FundamentDefaultUpdateDuration;
}

- (void) setDefaultUpdateInterval:(NSTimeInterval)defaultUpdateInterval {
  _defaultUpdateInterval = defaultUpdateInterval;
}

- (void) addTimer:(NSTimer *)timer forKey:(NSString *)key andExecuteImmediately:(BOOL)executeImmediately {
  [_timers setObject:timer forKey:key];
  if (executeImmediately) {
    [timer fire];
  }
}

- (NSTimer *) timerForDataSource:(FundamentDataSourceBlock)dataSource forKey:(NSString *)key 
              withUpdateInterval:(NSTimeInterval)updateInterval {
  NSMutableDictionary* userInfo = [NSMutableDictionary dictionary];
  
  [userInfo setObject:[[dataSource copy] autorelease] forKey:FundamentDataSourceKey];
  [userInfo setObject:[NSMutableDictionary dictionary] forKey:FundamentListenersKey];
  [userInfo setObject:[NSNumber numberWithInt:FundamentTimerStatusIdle] forKey:FundamentStatusKey];
  [userInfo setObject:[key copy] forKey:FundamentKeyKey];
  
  return [self timerWithUpdateInterval:updateInterval userInfo:userInfo];
}

- (NSTimer *) timerWithUpdateInterval:(NSTimeInterval)updateInterval userInfo:(NSDictionary *)userInfo {
  return [NSTimer scheduledTimerWithTimeInterval:updateInterval target:self selector:@selector(timerFired:) 
                                        userInfo:userInfo repeats:YES];
}

- (void) timerFired:(NSTimer *)timer {
  [self refreshDataSourceWithInfo:(NSMutableDictionary *)timer.userInfo];
}

- (void) refreshDataSourceWithInfo:(NSMutableDictionary *)info {
  [info setObject:[NSNumber numberWithInt:FundamentTimerStatusBusy] forKey:FundamentStatusKey];
  
  FundamentDataSourceBlock dataSource = [info objectForKey:FundamentDataSourceKey];
  FundamentSuccessBlock success = ^(id data) {
    NSDictionary* listeners = [info objectForKey:FundamentListenersKey];
    NSInteger listenerCount = 0;
    for (FundamentListener* listener in listeners.allValues) {
      FundamentLog(2, @"Calling listener %d for %@", listenerCount++, [info objectForKey:FundamentKeyKey]);
      [listener callWithData:data];
    }
    
    [info setObject:[NSNumber numberWithInt:FundamentTimerStatusIdle] forKey:FundamentStatusKey];
  };
  
  dataSource(success);
}

#pragma mark - Listeners

- (NSMutableDictionary *) observersForKey:(NSString *)key {
  return [[self infoForDataSourceWithKey:key] objectForKey:FundamentListenersKey];
}

- (BOOL) removeObserver:(NSString *)observerId dryRun:(BOOL)dryRun {
  for (NSString* dataSourceKey in _timers.allKeys) {
    NSMutableDictionary* observers = [self observersForKey:dataSourceKey];
    if (![observers objectForKey:observerId]) continue;
    if (dryRun) return YES;
    
    [observers removeObjectForKey:observerId]; break;
  }
  return NO;
}

- (void) removeObserver:(NSString *)observerId {
  [self removeObserver:observerId dryRun:NO];
}

// Master listener adder
- (NSString *) addObserverForKey:(NSString *)key 
           withFundamentListener:(FundamentListener *)listener 
                      observerId:(NSString *)observerId 
                 withNamespacing:(BOOL)namespacing 
                     overwriting:(BOOL)overwriting {
  NSString* finalObserverId = namespacing ? [NSString stringWithFormat:@"%@.%@", key, observerId] : observerId;
  
  // If there's a conflict, remove it (or, if the user doesn't want to overwrite, return)
  if ([self removeObserver:finalObserverId dryRun:!overwriting]) return nil;
  
  NSMutableDictionary* keyListeners = [self observersForKey:key];
  [keyListeners setObject:listener forKey:finalObserverId];
  
  FundamentLog(2, @"Added listener %@ for %@", finalObserverId, key);
  
  return finalObserverId;
}


- (NSString *) addObserverForKey:(NSString *)key withBlock:(FundamentCallback)block {
  NSString* observerId = nil;
  if (_descriptiveListenerIds) {
    // Interpolation strategy - numbered blocks within the given key. So, like Key.Block1, Key.Block2. Not much else we 
    // can use to identify a block.
    NSDictionary* currentObservers = [self observersForKey:key];
    NSInteger numberOfBlockObservers = 0;
    
    for (FundamentListener* listener in currentObservers.allValues) {
      if ([listener isKindOfClass:FundamentBlockListener.class]) ++numberOfBlockObservers;
    }
    
    observerId = [NSString stringWithFormat:@"Block%d", numberOfBlockObservers];
  } else {
    observerId = FundamentCreateUUID();
  }
  
  // Since these are the most likely to be used we won't send them through the indirection of the other variants.
  FundamentListener* observer = [[FundamentBlockListener alloc] initWithBlock:block];
  NSString* finalId = [self addObserverForKey:key 
                        withFundamentListener:observer
                                   observerId:observerId 
                              withNamespacing:YES 
                                  overwriting:YES];
  [observer release];
  
  return finalId;
}

- (NSString *) addObserverForKey:(NSString *)key withTarget:(id)target selector:(SEL)selector {
  NSString* observerId = nil;
  if (_descriptiveListenerIds) {
    // Interpolation strategy - use NSStringFromClass + NSStringFromSelector + Numbering
    NSDictionary* currentObservers = [self observersForKey:key];
    NSInteger numberOfSimilarObservers = 0;
    
    for (FundamentTargetSelListener* listener in currentObservers.allValues) {
      if (![listener isKindOfClass:FundamentTargetSelListener.class]) continue;
      if ([listener.target class] != [target class]) continue;
      if (listener.selector == selector) ++numberOfSimilarObservers;
    }
    
    observerId = [NSString stringWithFormat:@"%@_%@_%d", NSStringFromClass([target class]), 
                  NSStringFromSelector(selector), numberOfSimilarObservers];
  } else {
    observerId = FundamentCreateUUID();
  }
  
  FundamentListener* observer = [[FundamentTargetSelListener alloc] initWithTarget:target selector:selector];
  NSString* finalId = [self addObserverForKey:key 
                        withFundamentListener:observer
                                   observerId:observerId 
                              withNamespacing:YES 
                                  overwriting:YES];
  [observer release];
  
  return finalId;
}

// User specified IDs
- (NSString *) addObserverForKey:(NSString *)key 
                       withBlock:(FundamentCallback)observer 
                      observerId:(NSString *)observerId {
  return [self addObserverForKey:key withBlock:observer observerId:observerId withNamespacing:YES];
}
- (NSString *) addObserverForKey:(NSString *)key 
                      withTarget:(id)target 
                        selector:(SEL)selector 
                      observerId:(NSString *)observerId {
  return [self addObserverForKey:key withTarget:target selector:selector observerId:observerId withNamespacing:YES];
}

// User specified IDs, namespacing optional
- (NSString *) addObserverForKey:(NSString *)key 
                       withBlock:(FundamentCallback)observer 
                      observerId:(NSString *)observerId 
                 withNamespacing:(BOOL)namespacing {
  return [self addObserverForKey:key 
                       withBlock:observer 
                      observerId:observerId 
                 withNamespacing:namespacing 
                     overwriting:YES];
}

- (NSString *) addObserverForKey:(NSString *)key 
                      withTarget:(id)target 
                        selector:(SEL)selector 
                      observerId:(NSString *)observerId 
                 withNamespacing:(BOOL)namespacing {
  return [self addObserverForKey:key 
                      withTarget:target 
                        selector:selector 
                      observerId:observerId 
                 withNamespacing:namespacing 
                     overwriting:YES];
}

// User specified IDs, namespacing optional, overwriting optional
- (NSString *) addObserverForKey:(NSString *)key 
                       withBlock:(FundamentCallback)block
                      observerId:(NSString *)observerId 
                 withNamespacing:(BOOL)namespacing 
                     overwriting:(BOOL)overwriting {
  FundamentListener* observer = [[FundamentBlockListener alloc] initWithBlock:block];
  NSString* finalId = [self addObserverForKey:key 
                        withFundamentListener:observer 
                                   observerId:observerId 
                              withNamespacing:namespacing 
                                  overwriting:overwriting];
  [observer release];
  return finalId;
}
- (NSString *) addObserverForKey:(NSString *)key 
                      withTarget:(id)target 
                        selector:(SEL)selector 
                      observerId:(NSString *)observerId 
                 withNamespacing:(BOOL)namespacing 
                     overwriting:(BOOL)overwriting {
  FundamentListener* observer = [[FundamentTargetSelListener alloc] initWithTarget:target selector:selector];
  NSString* finalId = [self addObserverForKey:key 
                        withFundamentListener:observer 
                                   observerId:observerId 
                              withNamespacing:namespacing 
                                  overwriting:overwriting];
  [observer release];
  return finalId;
}

#pragma mark - Data Sources
#pragma mark Existing Info

- (NSMutableDictionary *) infoForDataSourceWithKey:(NSString *)key {
  NSTimer* timer = [_timers objectForKey:key];
  return timer ? (NSMutableDictionary *) timer.userInfo : nil;
}

- (FundamentTimerStatus) statusForDataSourceWithKey:(NSString *)key {
  return [[[self infoForDataSourceWithKey:key] objectForKey:FundamentStatusKey] intValue];
}

#pragma mark Generic

- (void) addDataSource:(FundamentDataSourceBlock)dataSource withUpdateInterval:(NSTimeInterval)updateInterval 
                forKey:(NSString *)key {
  NSTimer* timer = [self timerForDataSource:dataSource forKey:key withUpdateInterval:updateInterval];
  [self addTimer:timer forKey:key andExecuteImmediately:YES];
}

- (void) addDataSource:(FundamentDataSourceBlock)dataSource forKey:(NSString *)key {
  [self addDataSource:dataSource withUpdateInterval:self.defaultUpdateInterval forKey:key];
}

- (NSString *) addDataSource:(FundamentDataSourceBlock)dataSource {
  NSString* uuid = FundamentCreateUUID();
  [self addDataSource:dataSource forKey:uuid];
  return [uuid copy];
}

# pragma mark Generic URL

- (void) addURLDataSource:(NSURL *)dataSource 
         withResponseType:(FundamentResponseType)responseType 
           updateInterval:(NSTimeInterval)updateInterval
                   forKey:(NSString *)key {
  switch (responseType) {
    case FundamentResponseTypeJSON: {
      [self addWebDataSource:dataSource withParserBlock:FundamentParserJSON updateInterval:updateInterval forKey:key];
    } break;
    case FundamentResponseTypeData: {
      [self addWebDataSource:dataSource withParserBlock:FundamentParserData updateInterval:updateInterval forKey:key];
    } break;
    case FundamentResponseTypeImage: {
      [self addWebDataSource:dataSource withParserBlock:FundamentParserImage updateInterval:updateInterval forKey:key];
    } break;
    case FundamentResponseTypePlist:  {
      [self addWebDataSource:dataSource withParserBlock:FundamentParserPlist updateInterval:updateInterval forKey:key];
    } break;
    case FundamentResponseTypeString: {
      [self addWebDataSource:dataSource withParserBlock:FundamentParserString updateInterval:updateInterval forKey:key];
    } break;
    default: NSAssert(NO, @"Tried to add an unsupported responseType - %d", responseType);
  }
}

- (void) addWebDataSource:(NSURL *)dataSource withParserBlock:(FundamentParserBlock)parser 
                               updateInterval:(NSTimeInterval)updateInterval forKey:(NSString *)key {
  FundamentDataSourceBlock dataSourceBlock = ^(FundamentSuccessBlock success) {
    FundamentLog(2, @"Requesting DataSource - %@", dataSource);
    __block ASIHTTPRequest* request = [ASIHTTPRequest requestWithURL:dataSource];
    [request setCompletionBlock:^{
      FundamentLog(2, @"Got to Web Data Source Completion block for key - %@", key);
      success(parser(request));
    }];
    [request setFailedBlock:^{
      FundamentLog(1, @"Web Data Source Error - %@", request.error);
      success(nil);
    }];
    [request startAsynchronous];
  };
  
  [self addDataSource:dataSourceBlock withUpdateInterval:updateInterval forKey:key];
}

@end

#pragma mark - Internal Listener Implementatins
#pragma mark Base

@implementation FundamentListener

- (void) callWithData:(id)data {
  NSAssert(NO, @"Erroneous use of FundamentListener base class");
}

@end

#pragma mark Block

@implementation FundamentBlockListener 

@synthesize block = _block;

- (id) initWithBlock:(FundamentCallback)block {
  if ( !(self = [super init]) ) return nil;
  self.block = block;
  return self;
}

- (void) callWithData:(id)data {
  if (!!self.block) self.block(data);
}

- (void) dealloc {
  [_block release], _block = nil;
  [super dealloc];
}

@end

#pragma mark Target&Sel

@implementation FundamentTargetSelListener

@synthesize target = _target;
@synthesize selector = _selector;

- (id) initWithTarget:(id)target selector:(SEL)sel {
  if ( !(self = [super init]) ) return nil;
  self.target = target, self.selector = sel;
  return self;
}

- (void) callWithData:(id)data {
  if (self.target && [self.target respondsToSelector:self.selector]) {
    [self.target performSelector:self.selector withObject:data];
  }
}

@end


