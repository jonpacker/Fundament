//
//  Fundament.m
//  Fundament
//
//  Created by Jon Packer on 29/11/11.
//

#import "Fundament.h"
#import "JSONKit.h"

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

#pragma mark - UUID Generation

static NSString* FundamentCreateUUID() {
  CFUUIDRef uuidRef = CFUUIDCreate(kCFAllocatorDefault);
  NSString *uuidStr = [(NSString *)CFUUIDCreateString(kCFAllocatorDefault, uuidRef) autorelease];
  CFRelease(uuidRef);
  
  return uuidStr;
}

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

// Data source creator for a JSON data source
- (void) addJSONDataSource:(NSURL *)dataSource withResponseType:(FundamentResponseType)responseType;

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

#pragma mark - Object Lifecycle

- (id) init {
  if ( !(self = [super init]) ) {
    return nil;
  }
  
  [self createNotificationObservers];
  
  _dataSources = [[NSMutableDictionary alloc] init];
  _dataCache = [[NSCache alloc] init];
  
  return self;
}

- (void) dealloc {
  [_dataSources release], _dataSources = nil;
  [_dataCache release], _dataCache = nil;
  
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

#pragma mark - Data Sources
#pragma mark Generic

- (void) addDataSource:(FundamentDataSourceBlock)dataSource forKey:(NSString *)key {
  [_dataSources setObject:[[dataSource copy] autorelease] forKey:key];
}

- (NSString *) addDataSource:(FundamentDataSourceBlock)dataSource {
  NSString* uuid = FundamentCreateUUID();
  [self addDataSource:dataSource forKey:uuid];
  return [uuid copy];
}

# pragma mark Generic URL

- (void) addURLDataSource:(NSURL *)dataSource 
         withResponseType:(FundamentResponseType)responseType 
                   forKey:(NSString *)key {
  
}

# pragma mark JSON

- (void) addJSONDataSource:(NSURL *)dataSource withResponseType:(FundamentResponseType)responseType {
  
}

@end
