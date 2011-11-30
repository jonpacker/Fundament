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

// Data source creator for a JSON data source
- (void) addJSONDataSource:(NSURL *)dataSource withUpdateInterval:(NSTimeInterval)updateInterval 
                    forKey:(NSString *)key;

// Called when a timer fires, delegates the call off to where it should go.
- (void) timerFired:(NSTimer *)timer;

// Refreshes the data source contained in the given info.
- (void) refreshDataSourceWithInfo:(NSMutableDictionary *)info;

// Return the info for a certain data source's key
- (NSMutableDictionary *) infoForDataSourceWithKey:(NSString *)key;

// Return that status for a certain data source
- (FundamentTimerStatus) statusForDataSourceWithKey:(NSString *)key;

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
}

- (void) applicationDidEnterBackground:(NSNotification *)notification {
  FundamentLog(2, @"Application Did Enter Background");
}

#pragma mark - Timers

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
  [userInfo setObject:[NSMutableArray array] forKey:FundamentListenersKey];
  [userInfo setObject:[NSNumber numberWithInt:FundamentTimerStatusIdle] forKey:FundamentStatusKey];
  [userInfo setObject:[key copy] forKey:FundamentKeyKey];
  
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
    NSArray* listeners = [info objectForKey:FundamentListenersKey];
    for (FundamentListener* listener in listeners) {
      [listener callWithData:data];
    }
    
    [info setObject:[NSNumber numberWithInt:FundamentTimerStatusIdle] forKey:FundamentStatusKey];
  };
  
  dataSource(success);
}

#pragma mark - Listeners

//TODO - these will have to return some kind of opaque object. no other way for the user to remove them
- (void) addListenerWithBlock:(FundamentCallback)listener forKey:(NSString *)key {
  NSMutableArray* listeners = [[self infoForDataSourceWithKey:key] objectForKey:FundamentListenersKey];
  [listeners addObject:[[[FundamentBlockListener alloc] initWithBlock:listener] autorelease]];
}

- (void) addListenerWithTarget:(id)target selector:(SEL)selector forKey:(NSString *)key {
  NSMutableArray* listeners = [[self infoForDataSourceWithKey:key] objectForKey:FundamentListenersKey];
  [listeners addObject:[[[FundamentTargetSelListener alloc] initWithTarget:target selector:selector] autorelease]];
}

#pragma mark - Data Sources
#pragma mark Existing Info

- (NSMutableDictionary *) infoForDataSourceWithKey:(NSString *)key {
  NSTimer* timer = [_timers objectForKey:@"key"];
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
      [self addJSONDataSource:dataSource withUpdateInterval:updateInterval forKey:key];
    } break;
    default: NSAssert(NO, @"Tried to add an unsupported responseType - %@", responseType);
  }
}

# pragma mark JSON

- (void) addJSONDataSource:(NSURL *)dataSource withUpdateInterval:(NSTimeInterval)updateInterval 
                    forKey:(NSString *)key {
  FundamentDataSourceBlock dataSourceBlock = ^(FundamentSuccessBlock success) {
    __block ASIHTTPRequest* request = [[ASIHTTPRequest alloc] initWithURL:dataSource];
    [request setCompletionBlock:^{
      success([request.responseData objectFromJSONData]);
    }];
    [request setFailedBlock:^{
      success(nil);
    }];
    [[request autorelease] startAsynchronous];
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


