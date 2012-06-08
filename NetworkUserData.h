//
//  NetworkUserData.h
//  CalTalk
//

#import <Cocoa/Cocoa.h>


@interface NetworkUserData : NSObject
{
    NSNetService *m_userService;
    NSMutableArray *m_sharedCalendars;
    
    NSURLConnection *m_connection;
    NSURLAuthenticationChallenge *m_connectionAuthChallenge;
    NSMutableData *m_connectionData;
    NSMutableURLRequest *m_indexURLRequest;
	
    BOOL m_resolved, m_resolving, m_refreshPending;
}

// Initialize with the given NSNetService object, and immediately ask the host for the list of shared calendars
- initWithNetService: (NSNetService*)userService;
// Initialize with the given NSNetService, and fetch the shared calendars list if refreshCalendars is YES.
// Designated initializer
- initWithNetService: (NSNetService*)userService refreshSharedCalendars: (BOOL)refreshCalendars;

// Create an autoreleased NetworkUserData object using the corresponding init method above
+ (NetworkUserData*)userDataWithNetService: (NSNetService*)userService;
+ (NetworkUserData*)userDataWithNetService: (NSNetService*)userService
      refreshSharedCalendars: (BOOL)refreshCalendars;

// The receiver is equal to otherObject if [otherObject userService] is equal to [self userService]
- (BOOL)isEqual: (id)otherObject;
- (unsigned)hash;

// Reload the list of shared calendars from the user. Note that the list is refreshed asynchronously; a 
// change notification for the "sharedCalendars" key will be sent when the changed data arrives.
- (void)refreshSharedCalendars;

// Access the user's name, the NSNetService object for the user, and the list of calendars shared by the user
- (NSString*)userName;
- (NSNetService*)userService;
- (NSArray*)sharedCalendars;

// Return YES if the service's address has been resolved, NO otherwise
- (BOOL)resolved;

// Return a root URL for the user's service, or nil if the service is not resolved
- (NSURL*)URLForRoot;
// Return a URL by which the calendar with the given name can be retrieved from this user
- (NSURL*)URLForCalendar: (NSString*)calendar;

@end