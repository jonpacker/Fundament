//
//  Fundament.h
//  Fundament
//
//  Created by Jon Packer on 29/11/11.
//

#import <Foundation/Foundation.h>

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
// takes an (id) as your data to store. Got an error? No problem! Just ignore the callback.
typedef void (^FundamentSuccessBlock)(id data);
typedef void (^FundamentDataSourceBlock)(FundamentSuccessBlock success);

// These are the types of responses that we can receive. Of course, you can always plug in your own. No problem. This is
// just to make your life easier so you don't have to write the 1 line to parse some JSON!
typedef enum {
  FundamentResponseTypeJSON // corresponding string = "json"
} FundamentResponseType;

@interface Fundament : NSObject {
 @protected
  // Blocks are stored in here
  NSMutableDictionary* _dataSources;
  
  // Result of data source calls are stored in here. Since it's an NSCache the existence of a value isn't guaranteed,
  // which results in the need for all our data request calls to be async.
  NSCache* _dataCache;
}
 
// Access the shared instance of Fundament. 
+ (Fundament *) sharedFundament;

// Add the given data-source using a block that returns some data.
- (void) addDataSource:(FundamentDataSourceBlock)dataSource forKey:(NSString *)key;

// Add the given data-source, but generate a unique key for it, and return that. Each method will have one of these
// variants from now on, but no need for them to be documented as well.
- (NSString *) addDataSource:(FundamentDataSourceBlock)dataSource;

// Add the URL as a data-source, expecting the given response type.
- (void) addURLDataSource:(NSURL *)dataSource 
         withResponseType:(FundamentResponseType)responseType 
                   forKey:(NSString *)key;
- (NSString *) addURLDataSource:(NSURL *)dataSource withResponseType:(FundamentResponseType)responseType;

// Add URL data source from an NSDictionary. Should contain two keys, "format", and "url". "format" being one of the
// formats that translate to FundamentResponseType. See its documentation for corresponding strings.
- (void) addURLDataSourceWithDictionary:(NSDictionary *)dictionary forKey:(NSString *)key;
- (NSString *) addURLDataSourceWithDictionary:(NSDictionary *)dictionary;

// Add a bunch of URL data sources from an NSDictionary. Can contain any number of keys you want, the keys being the 
// identifiers that you will retrieve and observe the data with.
- (void) addURLDataSourcesWithDictionary:(NSDictionary *)dictionary;

@end
