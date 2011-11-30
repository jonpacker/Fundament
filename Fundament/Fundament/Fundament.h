//
//  Fundament.h
//  Fundament
//
//  Created by Jon Packer on 29/11/11.
//

#import <Foundation/Foundation.h>

/**
 * The default update duration (in seconds). If you don't specify an update duration, this fallback will be used. Note
 * that this is the fallback for the instance property defaultUpdateDuration. If you don't set that, that is when this 
 * value will be used. If you set it, it will override this.
 */
#define FundamentDefaultUpdateDuration 60

/**
 * The default config will contain a list of data sources to load by default on the shared fundament instance. They
 * will be loaded immediately as Fundament is (when +initialize is called). Format (obviously this can only be URL
 * data sources):
 {
  "datasource-name": {
    "format": "json",
    "url": "http://www.jonpacker.com/kaffe.json"
  },
  "other-datasource": {
    "format": "plist",
    "url": "http://www.jonpacker.com/kaffe.plist"
  }
 }
*/
#define FundamentDefaultConfig @"fundament" 

// Everything traces back to FundamentDataSourceBlock, pretty much. So it's pretty important. But it's nothing too 
// special. It just takes a callback argument (can you tell I use node much?) as a FundamentSuccessBlock - which just 
// takes an (id) as your data to store. 
typedef void (^FundamentSuccessBlock)(id data);
typedef void (^FundamentDataSourceBlock)(FundamentSuccessBlock success);

// Block type that is used as a callback when data is updated.
typedef void (^FundamentCallback)(id data);

// These are the types of responses that we can receive. Of course, you can always plug in your own. No problem. This is
// just to make your life easier so you don't have to write the 1 line to parse some JSON!
typedef enum {
  FundamentResponseTypeJSON,    // corresponding name = "json". Uses JSONKit to convert JSON to an NSDictionary/NSArray
  FundamentResponseTypeString,  // corresponding name = "string". Returns the raw output string.
  FundamentResponseTypeData,    // corresponding name = "data". Returns the raw NSData.
  FundamentResponseTypePlist,   // corresponding name = "plist". Uses built-in methods to read data as a plist.
  FundamentResponseTypeImage    // corresponding name = "image. Reads data as an image. 
} FundamentResponseType;

// These store the status of a timer. A timer can be busy, or idle. The timer is busy when it is making its call, and 
// becomes idle straight after until the next call.
typedef enum {
  FundamentTimerStatusIdle = 0,
  FundamentTimerStatusBusy = 1
} FundamentTimerStatus;

@interface Fundament : NSObject {
 @protected
  // Timers are stored in here. Blocks, listeners and statuses are stored in their userInfo.
  NSMutableDictionary* _timers;
  
  // Result of data source calls are stored in here. Since it's an NSCache the existence of a value isn't guaranteed,
  // which results in the need for all our data request calls to be async.
  NSCache* _dataCache;
  
 @private
  // Default time interval. If set to 0, #FundamentDefaultUpdateDuration will be used.
  NSTimeInterval _defaultUpdateInterval;
}

#pragma mark - Class Methods
 
// Access the shared instance of Fundament. 
+ (Fundament *) sharedFundament;

#pragma mark - Properties

// This value will be used when no value is specified.
@property (nonatomic, assign) NSTimeInterval defaultUpdateInterval;

#pragma mark - Instance Methods

// Add the given data-source using a block that returns some data. Will be fired according to updateInterval.
- (void) addDataSource:(FundamentDataSourceBlock)dataSource withUpdateInterval:(NSTimeInterval)updateInterval 
                forKey:(NSString *)key;

// Add the given data-source using a block that returns some data. Update interval will be set according to the default.
- (void) addDataSource:(FundamentDataSourceBlock)dataSource forKey:(NSString *)key;

// Add the given data-source, but generate a unique key for it, and return that. Each method will have one of these
// variants from now on, but no need for them to be documented as well. Update interval will be set to the default.
- (NSString *) addDataSource:(FundamentDataSourceBlock)dataSource;

// Add the URL as a data-source, expecting the given response type.
- (void) addURLDataSource:(NSURL *)dataSource 
         withResponseType:(FundamentResponseType)responseType 
           updateInterval:(NSTimeInterval)updateInterval
                   forKey:(NSString *)key;

// Add URL data source from an NSDictionary. Should contain two keys, "format", and "url". "format" being one of the
// formats that translate to FundamentResponseType. See its documentation for corresponding strings.
- (void) addURLDataSourceWithDictionary:(NSDictionary *)dictionary forKey:(NSString *)key;
- (NSString *) addURLDataSourceWithDictionary:(NSDictionary *)dictionary;

// Add a bunch of URL data sources from an NSDictionary. Can contain any number of keys you want, the keys being the 
// identifiers that you will retrieve and observe the data with.
- (void) addURLDataSourcesWithDictionary:(NSDictionary *)dictionary;

// Add a listener for the given key using a block
- (void) addListenerWithBlock:(FundamentCallback)listener forKey:(NSString *)key;

// Add a listener for the given key using a target & selector
- (void) addListenerWithTarget:(id)target selector:(SEL)selector forKey:(NSString *)key;

@end
