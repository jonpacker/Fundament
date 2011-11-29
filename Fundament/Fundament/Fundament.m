//
//  Fundament.m
//  Fundament
//
//  Created by Jon Packer on 29/11/11.
//

#import "Fundament.h"

#pragma mark - Logging

/**
 * Defines whether to show debug logging for Fundament. Likely for my own development purposes only, really.
 * 0 = Off
 * 1 = Errors
 * 2 = Info
 */
#define FundamentLogLevel 2

static inline void FundamentLog(NSString* format, ...) {
#if FundamentLogLevel > 0
  va_list args;
  va_start(args, format);
  NSLogv([NSString stringWithFormat:@"Fundament: %@", format], args); // There's probably a better way to do this...
  va_end(args);
#endif 
}

#pragma mark - Private Methods

@interface Fundament( PrivateMethods )

/**
 * Adds the instance as a listener to the application notifications that we're interested in - these are
 * - UIApplicationWillEnterForeground 
 * - UIApplicationDidEnterBackground
 */
- (void) createNotificationObservers;

@end

@implementation Fundament

#pragma mark - Class Methods & Static Stuff

static Fundament* sharedFundament = nil;

+ (void) initialize {
  sharedFundament = [[Fundament alloc] init];
}

+ (Fundament *) sharedFundament {
  return sharedFundament;
}

#pragma mark - Initialization

- (id) init {
  if ( !(self = [super init]) ) {
    return nil;
  }
  
  [self createNotificationObservers];
  
  return self;
}

- (void) createNotificationObservers {
  NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
  
  [center addObserver:self selector:@selector(applicationWillEnterForeground:) 
                 name:UIApplicationWillEnterForegroundNotification object:nil];
  [center addObserver:self selector:@selector(applicationDidEnterBackground:) 
                 name:UIApplicationDidEnterBackgroundNotification object:nil];
}

#pragma mark Application Observers

- (void) applicationWillEnterForeground:(NSNotification *)notification {
  FundamentLog(@"Application Will Enter Foreground");
}

- (void) applicationDidEnterBackground:(NSNotification *)notification {
  FundamentLog(@"Application Will Enter Foreground");
}


@end
