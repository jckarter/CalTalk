//
//  NetworkUserData.m
//  CalTalk
//

#import "CalTalk.h"
#import "CalTalkController.h"
#import "CalTalkData.h"
#import "NetworkUserData.h"
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

@interface NetworkUserData (Private)

// KVC array accessors
- (unsigned)countOfSharedCalendars;
- (NSString*)objectInSharedCalendarsAtIndex: (unsigned)idx;

// NSURLConnection delegate methods
- (void)connection: (NSURLConnection*)connection didFailWithError: (NSError*)error;
- (void)connection: (NSURLConnection*)connection didReceiveAuthenticationChallenge: (NSURLAuthenticationChallenge*)challenge;
- (void)connection: (NSURLConnection*)connection didReceiveData: (NSData*)data;
- (void)connectionDidFinishLoading: (NSURLConnection*)connection;
- (NSCachedURLResponse*)connection: (NSURLConnection*)connection willCacheResponse: (NSCachedURLResponse*)cachedResponse;

// Password sheet delegate method
- (void)passwordSheetDidEnd: (NSWindow*)sheet returnCode: (int)returnCode contextInfo: (void*)contextInfo;

// NSNetService delegate methods
- (void)netService: (NSNetService*)sender didNotResolve: (NSDictionary*)error;
- (void)netServiceDidResolveAddress: (NSNetService*)sender;

@end

#pragma mark -

@implementation NetworkUserData

// No automatic KVO notifications
+ (BOOL)automaticallyNotifiesObserversForKey: (NSString*)key
{
    return NO;
}

+ (void)initialize
{
    [self setKeys: [NSArray arrayWithObject: @"userService"]
	triggerChangeNotificationsForDependentKey: @"userName"];
}

- initWithNetService: (NSNetService*)netService
{
    return [self initWithNetService: netService refreshSharedCalendars: NO];
}

- initWithNetService: (NSNetService*)netService refreshSharedCalendars: (BOOL)refreshCalendars
{
    self = [super init];
    if(self)
    {
	m_indexURLRequest = nil;
	m_resolved = NO;
	m_resolving = YES;
	m_userService = [netService retain];
	m_sharedCalendars = [[NSMutableArray alloc] init];
	m_refreshPending = refreshCalendars;
	[netService setDelegate: self];
	if([netService respondsToSelector: @selector(resolveWithTimeout:)])
	    [netService resolveWithTimeout: 5];
	else
	    [netService resolve];
    }
    return self;
}

- (void)dealloc
{
    [m_userService release];
    [m_sharedCalendars release];
    [super dealloc];
}

+ (NetworkUserData*)userDataWithNetService: (NSNetService*)netService
{
    return [[[self alloc] initWithNetService: netService] autorelease];
}

+ (NetworkUserData*)userDataWithNetService: (NSNetService*)netService
      refreshSharedCalendars: (BOOL)refreshCalendars
{
    return [[[self alloc] initWithNetService: netService refreshSharedCalendars: refreshCalendars] autorelease];
}

- (BOOL)isEqual: (id)otherObject
{
    if(self == otherObject)
	return YES;
    if(![otherObject isKindOfClass: [NetworkUserData class]])
	return NO;
    return [m_userService isEqual: [otherObject userService]];
}

- (unsigned)hash
{
    return [m_userService hash];
}

- (void)refreshSharedCalendars
{
    if(!m_resolved)
    {
	m_refreshPending = YES;
	if(!m_resolving)
	{
	    m_resolving = YES;
	    if([m_userService respondsToSelector: @selector(resolveWithTimeout:)])
		[m_userService resolveWithTimeout: 5];
	    else
		[m_userService resolve];
	}
    }
    else
    {
	m_refreshPending = NO;

	if(m_connection)
	{
	    [m_connection cancel];
	    [m_connection release];
	    m_connection = nil;
	    [m_connectionAuthChallenge release];
	    m_connectionAuthChallenge = nil;
	    [m_connectionData release];
	    m_connectionData = nil;
	}

	NSURL *indexURL = [NSURL URLWithString: @"/index.plist" relativeToURL: [self URLForRoot]];
	NSMutableURLRequest *indexURLRequest = [[NSMutableURLRequest alloc] initWithURL: indexURL
									    cachePolicy: NSURLRequestUseProtocolCachePolicy
									    timeoutInterval: 60.0];
	[indexURLRequest setValue: [NSString stringWithFormat: @"CalTalk/%@",
							       [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleVersion"]]
			 forHTTPHeaderField: @"User-Agent"];
	
	m_connectionAuthChallenge = nil;
	m_connectionData = [[NSMutableData alloc] init];
	m_connection = [[NSURLConnection alloc] initWithRequest: indexURLRequest
						delegate: self];

	// XXX
	NSLog(@"request %p (%@); connection %p (%@)\n", indexURLRequest, [indexURLRequest description],
							m_connection,    [m_connection description]);

	[[g_calTalkController content] addJobToProgress: [NSString stringWithFormat: NSLocalizedString(@"Refreshing %@", @""), [m_userService name]]];	
	// NSURLConnection will call us back at the connection*: delegate methods
    }
}

- (NSString*)userName
{
    return [m_userService name];
}

- (NSNetService*)userService
{
    return m_userService;
}

- (NSArray*)sharedCalendars
{
    return m_sharedCalendars;
}

- (BOOL)resolved
{
	return m_resolved;
}

- (NSURL*)URLForRoot
{
    NSArray *serviceAddrs;
    NSEnumerator *serviceAddrsEnum;
    NSData *serviceAddrData;
    const struct sockaddr_in *serviceAddr = NULL;
    const char *serviceInAddr;
    NSURL *retval;
	
    if(!m_resolved)
	return nil;

    // Find the first resolved IPv4 address
    serviceAddrs = [m_userService addresses];
    serviceAddrsEnum = [serviceAddrs objectEnumerator];
	
    while(serviceAddrData = [serviceAddrsEnum nextObject])
    {
	serviceAddr = [serviceAddrData bytes];
	if(serviceAddr->sin_family == AF_INET)
	    break;
	else
	    serviceAddr = NULL;
    }
    if(!serviceAddr)
	return nil;
    // If we got a hostname in the resolve, use that. Otherwise, use the numeric IP address
    // Lock to protect the thread-unsafe inet_ntoa call
    @synchronized(g_calTalkController)
    {
	if([m_userService respondsToSelector: @selector(hostName)] && [m_userService hostName] != nil)
	    serviceInAddr = [[m_userService hostName] UTF8String];
	else
	    serviceInAddr = inet_ntoa(serviceAddr->sin_addr);
	
	retval = [NSURL URLWithString: [NSString stringWithFormat: @"http://%s:%u/", serviceInAddr, serviceAddr->sin_port]];
    }
    
    return retval;
}

- (NSURL*)URLForCalendar: (NSString*)calendar
{
    NSURL *root = [self URLForRoot];
    
    if(!root)
	return nil;
		
    return [NSURL URLWithString:
		   [[calendar stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding] stringByAppendingString:
		       @".ics"] relativeToURL: [self URLForRoot]];
}

@end

#pragma mark -

@implementation NetworkUserData (Private)

- (unsigned)countOfSharedCalendars
{
    return [m_sharedCalendars count];
}

- (NSString*)objectInSharedCalendarsAtIndex: (unsigned)idx
{
    return [m_sharedCalendars objectAtIndex: idx];
}

- (void)connection: (NSURLConnection*)connection didFailWithError: (NSError*)error
{
    //NSLog(@"[NetworkUserData %p] connection: %p didFailWithError: %p\n", self, connection, error);

    [[g_calTalkController content] removeJobFromProgress: [NSString stringWithFormat: NSLocalizedString(@"Refreshing %@", @""), [m_userService name]]];
    
    // If the user cancelled authentication, we already know about it
    if(!(m_connectionAuthChallenge != nil
         && [error domain] == NSURLErrorDomain
         && [error code] == NSURLErrorUserCancelledAuthentication))
    {
	[[NSAlert alertWithMessageText: NSLocalizedString(@"Error Getting Calendars", @"")
		  defaultButton: @"OK" alternateButton: nil otherButton: nil
		  informativeTextWithFormat:
		    [NSString stringWithFormat: NSLocalizedString(@"There was an error fetching %@'s list of calendars:\n\n%@", @""),
						[m_userService name], [error localizedDescription]]] //XXX use localizedFailureReason instead?
	    beginSheetModalForWindow: [g_calTalkController calendarsWindow] modalDelegate: g_calTalkController
	    didEndSelector: @selector(throwAwayAlertDidEnd:returnCode:contextInfo:) contextInfo: NULL];
    }
    [m_connection release];
    m_connection = nil;
    [m_connectionAuthChallenge release];
    m_connectionAuthChallenge = nil;
    [m_connectionData release];
    m_connectionData = nil;
}

- (void)connection: (NSURLConnection*)connection didReceiveAuthenticationChallenge: (NSURLAuthenticationChallenge*)challenge
{
    //NSLog(@"[NetworkUserData %p] connection: %p didReceiveAuthenticationChallenge: %p\n", self, connection, challenge);
    m_connectionAuthChallenge = [challenge retain];
    // We'll answer the auth request when the password sheet is filled out
    [NSApp beginSheet: [g_calTalkController passwordPanel]
	   modalForWindow: [g_calTalkController calendarsWindow]
	   modalDelegate: self
	   didEndSelector: @selector(passwordSheetDidEnd:returnCode:contextInfo:)
	   contextInfo: NULL];
}

- (void)connection: (NSURLConnection*)connection didReceiveData: (NSData*)data
{
    //NSLog(@"[NetworkUserData %p] connection: %p didReceiveData: %p\n", self, connection, data);
    [m_connectionData appendData: data];
}

- (void)connectionDidFinishLoading: (NSURLConnection*)connection
{
    //NSLog(@"[NetworkUserData %p] connectionDidFinishLoading: %p\n", self, connection);
    NSString *plistErrorDescription = nil;
    NSArray *indexArray = [NSPropertyListSerialization propertyListFromData: m_connectionData
						       mutabilityOption: NSPropertyListImmutable
						       format: NULL
						       errorDescription: &plistErrorDescription];
    NSEnumerator *indexArrayEnum;
    id indexArrayObject;
    NSRange kvoRange;
    
    // Validate the plist. It should be an NSArray of NSStrings
    if(!indexArray || ![indexArray isKindOfClass: [NSArray class]])
	return;
    indexArrayEnum = [indexArray objectEnumerator];
    while(indexArrayObject = [indexArrayEnum nextObject])
    {
	if(![indexArrayObject isKindOfClass: [NSString class]])
	    return;
    }
    
    // Clear out the old array of calendars and bring in the new
    kvoRange.location = 0;
    kvoRange.length = [m_sharedCalendars count];
    [self willChange: NSKeyValueChangeRemoval
	  valuesAtIndexes: [NSIndexSet indexSetWithIndexesInRange: kvoRange]
	  forKey: @"sharedCalendars"];
    [m_sharedCalendars removeAllObjects];
    [self didChange: NSKeyValueChangeRemoval
	  valuesAtIndexes: [NSIndexSet indexSetWithIndexesInRange: kvoRange]
	  forKey: @"sharedCalendars"];
    
    kvoRange.location = 0;
    kvoRange.length = [indexArray count];
    [self willChange: NSKeyValueChangeInsertion
	  valuesAtIndexes: [NSIndexSet indexSetWithIndexesInRange: kvoRange]
	  forKey: @"sharedCalendars"];
    [m_sharedCalendars addObjectsFromArray: indexArray];
    [self didChange: NSKeyValueChangeInsertion
	  valuesAtIndexes: [NSIndexSet indexSetWithIndexesInRange: kvoRange]
	  forKey: @"sharedCalendars"];

    [[g_calTalkController content] removeJobFromProgress: [NSString stringWithFormat: NSLocalizedString(@"Refreshing %@", @""), [m_userService name]]];
    [m_connection release];
    m_connection = nil;
    [m_connectionAuthChallenge release];
    m_connectionAuthChallenge = nil;
    [m_connectionData release];
    m_connectionData = nil;
}

- (NSCachedURLResponse*)connection: (NSURLConnection*)connection willCacheResponse: (NSCachedURLResponse*)cachedResponse
{
    //NSLog(@"[NetworkUserData %p] connection: %p willCacheResponse: %p\n", self, connection, cachedResponse);
    return nil;
}

- (void)passwordSheetDidEnd: (NSWindow*)sheet returnCode: (int)returnCode contextInfo: (void*)contextInfo
{
    if(returnCode == 1) // Login
    {
	NSString *username = [[g_calTalkController passwordPanelUsernameTextField] stringValue],
		 *password = [[g_calTalkController passwordPanelPasswordTextField] stringValue];
	BOOL storeInKeychain = ([[g_calTalkController passwordPanelStoreInKeychainButton] state] == NSOnState);
	
	[[m_connectionAuthChallenge sender]
	    useCredential: [NSURLCredential credentialWithUser: username
					    password: password
					    persistence: (storeInKeychain? NSURLCredentialPersistencePermanent : NSURLCredentialPersistenceForSession)]
	    forAuthenticationChallenge: m_connectionAuthChallenge];
	[m_connectionAuthChallenge release];
	m_connectionAuthChallenge = nil;
    }
    else if(returnCode == 2) // Cancel
    {
	[[m_connectionAuthChallenge sender] cancelAuthenticationChallenge: m_connectionAuthChallenge];
   }
    else
    {
	NSLog(@"Illegal button in Password sheet!\n");
    }
    [sheet orderOut: self];
}

- (void)netService: (NSNetService*)sender didNotResolve: (NSDictionary*)error
{
    // XXX indicate error somehow
    NSLog(@"Service %@ did not resolve: %@\n", [sender description], [error description]);
    m_resolving = NO;
    [sender stop];
}

- (void)netServiceDidResolveAddress: (NSNetService*)sender
{
    [self willChangeValueForKey: @"resolved"];
    m_resolved = YES;
    [self didChangeValueForKey: @"resolved"];
    m_resolving = NO;
    if(m_refreshPending)
	[self refreshSharedCalendars];
    [sender stop];
}

@end