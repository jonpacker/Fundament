//
//  Fundament.h
//  Fundament
//
//  Created by Jon Packer on 29/11/11.
//

#import <Foundation/Foundation.h>

/**
 * A macro to use for convenience rather than having to use the rather long winded [Fundament sharedFundament] every
 * time you want to access the default singleton.
 */
#define $Fundament [Fundament sharedFundament]

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
 @public 
  // Whether descriptive names are attempted for listener IDs interpolation
  // _descriptiveListenerIds = YES: "DataSourceKey.DataTableViewController_updateData:"
  // _descriptiveListenerIds =  NO: "DataSourceKey.550e8400-e29b-41d4-a716-446655440000"
  BOOL _descriptiveListenerIds;
  
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

// Event listeners! These observers will be called each time their corresponding dataSource is updated. An ID is
// returned that is needed to remove block listeners (but can be also used for target/sel if you want). 
//
// The easiest thing to do with IDs is to ignore them completely and only use the returned IDs as a way to remove a 
// observer. If you want to do that, you don't need to read the next two paragraphs.
//
// You can specify your own ID if you like, but note that it will be namespaced in front of the data source's key. That 
// means if you pass an ID 'myDataTable' to a listener for data source with key 'dataTableSource', your resulting key 
// will be: 'dataTableSource.myDataTable'. You can override namespace by calling the variant with 'withNamespacing' in
// the signature - but note that this will overwrite any other listener in this Fundament instance with the same ID.
//
// ID's are also useful in overwriting old listeners. If you add a new listener for a data source with the same key as
// the old one, the old one will first be removed before the new one is added. You can override this by calling the
// variant with 'overwriting' in the signature. If overwriting is turned off and you try to add a listener with the same
// name, no action will be taken and the listener will not be added (you kind of have to back yourself into a corner for
// this case to occur). If that conflict happens, nil will be returned.
//
// An example of adding a listener might be:
//
// NSString* listenerId = [$Fundament addListenerWithTarget:self 
//                                                 selector:@selector(dataUpdated:) 
//                                                   forKey:@"DataSourceKey"];
//
// You might store 'listener' as an instance variable. Then, later, when you want to remove it, you would do:
//
// [$Fundament removeListener:listenerId]
//
// Because the ID is namespaced, this will always find the correct listener
//
// These methods all perform a similar purpose, with different idioms and nomenclature. Their effect is the same though
// so they only need to be documented once.

// Default selectors, easiest to use. Generates a unique ID manually.
- (NSString *) addObserverForKey:(NSString *)key withBlock:(FundamentCallback)observer;
- (NSString *) addObserverForKey:(NSString *)key withTarget:(id)target selector:(SEL)selector;

// User specified IDs
- (NSString *) addObserverForKey:(NSString *)key 
                       withBlock:(FundamentCallback)observer 
                      observerId:(NSString *)observerId;
- (NSString *) addObserverForKey:(NSString *)key 
                      withTarget:(id)target 
                        selector:(SEL)selector 
                      observerId:(NSString *)observerId;

// User specified IDs, namespacing optional
- (NSString *) addObserverForKey:(NSString *)key 
                       withBlock:(FundamentCallback)observer 
                      observerId:(NSString *)observerId 
                 withNamespacing:(BOOL)namespacing;
- (NSString *) addObserverForKey:(NSString *)key 
                      withTarget:(id)target 
                        selector:(SEL)selector 
                      observerId:(NSString *)observerId 
                 withNamespacing:(BOOL)namespacing;

// User specified IDs, namespacing optional, overwriting optional
- (NSString *) addObserverForKey:(NSString *)key 
                       withBlock:(FundamentCallback)observer 
                      observerId:(NSString *)observerId 
                 withNamespacing:(BOOL)namespacing 
                     overwriting:(BOOL)overwriting;
- (NSString *) addObserverForKey:(NSString *)key 
                      withTarget:(id)target 
                        selector:(SEL)selector 
                      observerId:(NSString *)observerId 
                 withNamespacing:(BOOL)namespacing 
                     overwriting:(BOOL)overwriting;

// Observer removal. Much simpler!
- (void) removeObserver:(NSString *)observerId;


@end
