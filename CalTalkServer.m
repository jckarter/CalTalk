//
//  HTTPServer.m
//  CalTalk
//

#import "CalTalk.h"
#import "CalTalkServer.h"
#import "CalTalkData.h"
#import "ServerDigestClient.h"
#import "SharedCalendarData.h"
#import "CalTalkController.h"
#import "NSData_HexRepresentation.h"
#import <string.h>
#import <DNSServiceDiscovery/DNSServiceDiscovery.h>
#import <openssl/bio.h>
#import <openssl/evp.h>
#import <sys/errno.h>
#import <sys/types.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <strings.h>
#import <string.h>

// How many seconds to keep digest client entries after their last access
#define CALTALKSERVER_KEEP_DIGEST_CLIENT_SECONDS (30.0*60)
#define CALTALKSERVER_EXPIRE_DIGEST_CLIENT_SECONDS (5.0*60)

static NSString *CalTalkServer_base64StringFromData(NSData *data); // XXX define
static NSData *CalTalkServer_dataFromBase64String(NSString *base64String);

@interface CalTalkServer (Private)

// Try starting the server again from an NSTimer
- (void)startFromTimer: (NSTimer*)timer;

// Publish the Rendezvous service
- (void)publish;

// Delegate methods for NSSocketPort
- (void)netServiceWillPublish: (NSNetService*)sender;
- (void)netServiceDidStop: (NSNetService*)sender;
- (void)netService: (NSNetService*)sender didNotPublish: (NSDictionary*)errDict;

// Build a response to the given request
- (HTTPResponse*)responseForRequest: (HTTPRequest*)request fromAddress: (NSString*)fromAddress;
// Build a response for "GET /index.plist" requests
- (HTTPResponse*)responseForIndexRequest;
// Build a response for "GET /*.ics" requests
- (HTTPResponse*)responseForCalendarRequest: (NSString*)path;
// Build an error response
- (HTTPResponse*)responseForErrorStatus: (unsigned)status message: (NSString*)message;
// Build a 401 Unauthorized response
- (HTTPResponse*)responseForUnauthorizedRequest: (HTTPRequest*)request fromAddress: (NSString*)fromAddress stale: (BOOL)isStale;

// Check if the given request matches Basic and Digest auth credentials
- (BOOL)requestMatchesBasicCredentials: (HTTPRequest*)request;
- (BOOL)requestMatchesDigestCredentials: (HTTPRequest*)request fromAddress: (NSString*)fromAddress stale: (BOOL*)stale;

// Handle an incoming connection notification
- (void)listenSocketConnectionAcceptedNotification: (NSNotification*)notification;

// Read and dispatch the request data from a file handle in a thread. The method takes ownership
// of the passed file handle and closes and releases it when done.
- (void)readAndAnswerRequestFromFileHandle: (NSFileHandle*)fileHandle;

// Handle changes to user preferences
- (void)observeValueForKeyPath: (NSString*)keyPath ofObject: (id)object change: (NSDictionary*)change context: (void*)context; 

// Get the ServerDigestClient object for the given address, or return nil if it doesn't exist
- (ServerDigestClient*)digestClientForAddress: (NSString*)address;
// Make a new ServerDigestClient object for the given address
- (ServerDigestClient*)newDigestClientForAddress: (NSString*)address;
// Maintain the list of digest clients, removing entries that haven't been used in a while
- (void)maintainDigestClients: (NSTimer*)timer;

// Modal delegate method for the server start error alert
- (void)startErrorAlertDidEnd: (NSAlert*)alert returnCode: (int)returnCode contextInfo: (void*)alternatePort;

@end

#pragma mark -

@implementation CalTalkServer

- initWithController: (CalTalkController*)controller
{
    self = [super init];
    if(self)
    {
	m_serverCreateDate = [[NSDate alloc] init];
	
	m_listenSocket = nil;
	m_netService = nil;
	
	m_calTalkController = [controller retain];
	m_passwordController = [controller passwordController];
	
	id userDefaultsController = [NSUserDefaultsController sharedUserDefaultsController];
	m_serverName = [[userDefaultsController valueForKeyPath: @"values.shareName"] retain];
	m_port = [[userDefaultsController valueForKeyPath: @"values.sharePort"] intValue];
	m_serverNameNumber = 0;
	
	m_digestClients = [[NSMutableDictionary alloc] init];
	m_maintainDigestClientsTimer = [[NSTimer scheduledTimerWithTimeInterval: 60.0
						 target: self
						 selector: @selector(maintainDigestClients:)
						 userInfo: nil
						 repeats: YES] retain];
	
	// Observe the shareName and sharePort keys so that we can change our name and port if the user asks
	[userDefaultsController addObserver: self forKeyPath: @"values.shareName" options: NSKeyValueObservingOptionNew context: NULL];
	[userDefaultsController addObserver: self forKeyPath: @"values.sharePort" options: NSKeyValueObservingOptionNew context: NULL];
	
	m_serverRunning = NO;
	m_serverPublished = NO;
    }
    return self;
}

- (void)dealloc
{
    if(m_serverRunning)
	[self stop];
    [m_listenSocket release];
    [m_netService release];
    [m_serverName release];
    [m_maintainDigestClientsTimer invalidate];
    [m_maintainDigestClientsTimer release];
    [m_digestClients release];

    [super dealloc];
}

- (BOOL)serverRunning
{
    return m_serverRunning;
}

- (BOOL)serverPublished
{
    return m_serverPublished;
}

- (NSString*)serverName
{
    return m_serverName;
}

- (unsigned)port
{
    return m_port;
}

- (NSNetService*)netService
{
    return m_netService;
}

- (void)start
{
    char errorString[256];
    int listenSock, err;
    
    if(!m_serverRunning)
    {
	// Open the listen socket
	listenSock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	err = 0;
	
	if(listenSock < 0)
	{
	    err = errno;
	    goto socketError;
	}
	struct sockaddr_in listenSockAddr;
	bzero(&listenSockAddr, sizeof(listenSockAddr));
	listenSockAddr.sin_family = AF_INET;
	listenSockAddr.sin_addr.s_addr = INADDR_ANY;
	listenSockAddr.sin_port = m_port;
	listenSockAddr.sin_len = sizeof(listenSockAddr);
	if(bind(listenSock, (struct sockaddr *)&listenSockAddr, sizeof(listenSockAddr)) < 0)
	{
	    err = errno;
	    goto socketError;
	}
	if(listen(listenSock, 5) < 0)
	{
	    err = errno;
	    goto socketError;
	}

	m_listenSocket = [[NSFileHandle alloc] initWithFileDescriptor: listenSock];
	if(!m_listenSocket)
	{
	    err = ENOMEM;
	    goto socketError;
	}
	
	// Observe notifications on the listen socket
	[[NSNotificationCenter defaultCenter] addObserver: self
	    selector: @selector(listenSocketConnectionAcceptedNotification:)
	    name: NSFileHandleConnectionAcceptedNotification object: m_listenSocket];
	
	[self publish];
	
	// Start accepting connections
	[m_listenSocket acceptConnectionInBackgroundAndNotify];
	m_serverRunning = YES;
    }
    
    return;
    
socketError:
    strerror_r(err, errorString, 255);
    
    if(listenSock >= 0)
	close(listenSock);
    [m_listenSocket release];
    m_listenSocket = nil;

    unsigned short alternatePort = m_port + 1;
    if(alternatePort < 1025)
	alternatePort = m_port - 1;

    NSAlert *startErrorAlert 
	= [NSAlert alertWithMessageText: NSLocalizedString(@"Error sharing calendars", @"")
		   defaultButton:   [NSString stringWithFormat: NSLocalizedString(@"Try %u Again", @""),   m_port]
		   alternateButton:     NSLocalizedString(@"Don't Share", @"")
		   otherButton: [NSString stringWithFormat: NSLocalizedString(@"Try %u Instead", @""), alternatePort]
		   informativeTextWithFormat: [NSString stringWithFormat:
						 NSLocalizedString(@"There was an error starting the calendar sharing server. "
								    "Another application (possibly another user on this machine "
								    "running CalTalk) could be using port %u. You may try using "
								    "port %u again, try a different port, or turn off sharing "
								    "altogether.\n\n"
								    "Note that using a different port number will require "
								    "any users already subscribed to your calendars to resubscribe.", @""),
						 m_port, m_port]];
    if(![m_calTalkController calendarsWindow] || ![[m_calTalkController calendarsWindow] isVisible])
    {
	int returnCode = [startErrorAlert runModal];
	[self startErrorAlertDidEnd: startErrorAlert returnCode: returnCode contextInfo: (void*)alternatePort];
    }
    else
    {
	[startErrorAlert beginSheetModalForWindow: [m_calTalkController calendarsWindow]
			 modalDelegate: self
			 didEndSelector: @selector(startErrorAlertDidEnd:returnCode:contextInfo:)
			 contextInfo: (void*)alternatePort];
    }
}

- (void)stop
{
    if(m_serverRunning)
    {
	// Unpublish the service
	[m_netService stop];
	[m_netService release];
	m_netService = nil;
	
	m_serverNameNumber = 0;
	
	// Release the listen socket
	m_serverRunning = NO;
	[m_listenSocket closeFile];
	[m_listenSocket release];
	m_listenSocket = nil;
	
	// Stop observing notifications on the listen socket
	[[NSNotificationCenter defaultCenter] removeObserver: self];
    }
}
	
- (void)restart
{
    [self stop];
    [self start];
}

@end

#pragma mark -

@implementation CalTalkServer (Private)

- (void)startFromTimer: (NSTimer*)timer
{
    [self start];
}

- (void)publish
{
    // Publish the service
    NSMutableString *publishName = [NSMutableString stringWithString: m_serverName];
    if(m_serverNameNumber > 0)
	[publishName appendFormat: @" %d", m_serverNameNumber];
    m_netService = [[NSNetService alloc] initWithDomain: @"" type: CALTALK_SERVICE_TYPE
		       name: publishName port: m_port];
    [m_netService setDelegate: self];
    [m_netService publish];
}

- (void)netServiceWillPublish: (NSNetService*)sender
{
    m_serverPublished = YES;
}

- (void)netServiceDidStop: (NSNetService*)sender
{
    m_serverPublished = NO;
}

- (void)netService: (NSNetService*)sender didNotPublish: (NSDictionary*)errDict
{
    int errorCode = [[errDict objectForKey: NSNetServicesErrorCode] intValue];
    
    m_serverPublished = NO;
    
    if(errorCode == kDNSServiceDiscoveryNameConflict || errorCode == NSNetServicesCollisionError)
    {
	[m_netService release];
	m_netService = nil;
	++m_serverNameNumber;
	[self publish];
    }
    else
	NSLog(@"Error registering Rendezvous service: %@\n", [errDict description]);
}

- (HTTPResponse*)responseForRequest: (HTTPRequest*)request fromAddress: (NSString*)fromAddress
{
    NSString *requestPath = [request path];

    // Request must be valid
    if(!request)
	return [self responseForErrorStatus: 400 message: @"Your request was improperly formed."];
	
    // We only accept GET requests
    if(![[request method] isEqualToString: @"GET"])
	return [self responseForErrorStatus: 405 message: @"This server only accepts GET requests."];
    
    // See whether the user is authorized
    if([m_passwordController hasPassword])
    {
	if([request valueForHeader: @"authorization"] == nil)
	    return [self responseForUnauthorizedRequest: request fromAddress: fromAddress stale: NO];
	
	BOOL passedAuthentication, stale;
	if([[[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath: @"values.secDigestAuth"] boolValue])
	    passedAuthentication = [self requestMatchesDigestCredentials: request fromAddress: fromAddress stale: &stale];
	else
	{
	    passedAuthentication = [self requestMatchesBasicCredentials: request];
	    stale = NO;
	}
	if(!passedAuthentication)
	    return [self responseForUnauthorizedRequest: request fromAddress: fromAddress stale: stale];
    }
    
    if([requestPath isEqualToString: @"/index.plist"])
	return [self responseForIndexRequest];
    if([[requestPath pathComponents] count] == 2 && [[requestPath pathExtension] isEqualToString: @"ics"])
	return [self responseForCalendarRequest: requestPath];
    
    return [self responseForErrorStatus: 404 message: @"The requested object isn't available on this server."];
}

- (HTTPResponse*)responseForIndexRequest
{
    NSArray *calendarDataArray;
    NSEnumerator *calendarDataEnum;
    SharedCalendarData *calendarData;
    NSMutableArray *plistArray;
    NSData *indexPageData;
    NSString *plistError;

    /* -[NSPropertyListSerialization dataFromPropertyList:É] in Panther doesn't clear the errorDescription:
     * argument when there's no error */
    plistError = nil;
    /* Get only the calendars that are being shared */
    calendarDataArray = [[m_calTalkController content] myCalendars];
    plistArray = [NSMutableArray arrayWithCapacity: [calendarDataArray count]];
    calendarDataEnum = [calendarDataArray objectEnumerator];
    while((calendarData = [calendarDataEnum nextObject]))
    {
	if([calendarData calendarShared])
	    [plistArray addObject: [calendarData calendarName]];
    }
	
    indexPageData = [NSPropertyListSerialization dataFromPropertyList: plistArray format: NSPropertyListXMLFormat_v1_0
			errorDescription: &plistError];
    if(plistError)
    {
	return [self responseForErrorStatus: 500 message: [NSString stringWithFormat: @"Internal server error: %@", plistError]];
	[plistError release];
    }
    else
	return [[[HTTPResponse alloc] initWithVersion: @"HTTP/1.0" status: 200
				      headers: [NSDictionary dictionaryWithObjectsAndKeys:
						   @"text/plain; charset=utf8",	@"content-type",
						   @"close",			@"connection",
						   nil]
				      body: indexPageData] autorelease];
}

- (HTTPResponse*)responseForCalendarRequest: (NSString*)path
{
    NSArray *calendarDataArray;
    NSEnumerator *calendarDataEnum;
    SharedCalendarData *calendarData;
    NSString *calendarName, *calendarFileName;
    NSData *calendarFileData, *responseData;

    calendarName = [[path lastPathComponent] stringByDeletingPathExtension];
    calendarDataArray = [[m_calTalkController content] myCalendars];
    calendarDataEnum = [calendarDataArray objectEnumerator];
    calendarFileName = nil;
    
    while((calendarData = [calendarDataEnum nextObject]))
    if([calendarData calendarShared]
       && [[[calendarData calendarName] uppercaseString] isEqualToString: [calendarName uppercaseString]])
    {
	calendarFileName = [calendarData calendarFileName];
	break;
    }
    if(!calendarFileName)
	return [self responseForErrorStatus: 404 message: @"The requested calendar does not exist on this server."];
    calendarFileData = [NSData dataWithContentsOfFile: calendarFileName];
    if(!calendarFileData)
	return [self responseForErrorStatus: 500
		     message: [NSString stringWithFormat: @"Internal server error reading calendar %@", calendarName]];

    NSUserDefaultsController *sharedController = [NSUserDefaultsController sharedUserDefaultsController];

    NSMutableString *calendarFileString = [[[NSMutableString alloc] initWithData: calendarFileData encoding: NSUTF8StringEncoding] autorelease];
    NSRange calNameRange;
    unsigned calNameEnd;
    calNameRange = [calendarFileString rangeOfString: @"\nX-WR-CALNAME:" options: NSCaseInsensitiveSearch];
    if(calNameRange.location != NSNotFound)
    {
	// If the "Add to name" preference is set, add our login name (or the user's custom text) to the end of
	// the calendar name
	if([[sharedController valueForKeyPath: @"values.addToName"] boolValue])
	{
	    calNameRange.location += calNameRange.length;
	    calNameEnd = [calendarFileString rangeOfString: @"\n" options: 0 range: NSMakeRange(calNameRange.location, [calendarFileString length] - calNameRange.location)].location;
	    // Backtrack over any trailing whitespace
	    while([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember: [calendarFileString characterAtIndex: calNameEnd]])
		--calNameEnd;
	    ++calNameEnd;
	    [calendarFileString replaceCharactersInRange: NSMakeRange(calNameEnd, 0)
				withString: [@" " stringByAppendingString: [sharedController valueForKeyPath: @"values.addToNameText"]]];
	}
    }
    else
    {
	// iCal 2.0 on Tiger doesn't keep an X-WR-CALNAME header in its corestorage.ics files, so we add one
	// ourselves
	calNameRange = [calendarFileString rangeOfString: @"BEGIN:VCALENDAR" options: NSCaseInsensitiveSearch];
	if(calNameRange.location == NSNotFound)
	{
	    NSLog(@"Calendar file doesn't have a BEGIN:VCALENDAR line!\n");
	    calNameRange.location = 0;
	}
	else
	{
	    calNameRange.location += calNameRange.length;
	    // Skip to the line after the BEGIN:VCALENDAR declaration
	    while([calendarFileString characterAtIndex: calNameRange.location] != '\n')
		++calNameRange.location;
	    ++calNameRange.location;
	}
	calNameRange.length = 0;
	    
	NSString *calNameString;
	if([[sharedController valueForKeyPath: @"values.addToName"] boolValue])
	    calNameString = [NSString stringWithFormat: @"X-WR-CALNAME:%@ %@\r\n", calendarName, [sharedController valueForKeyPath: @"values.addToNameText"]];
	else
	    calNameString = [NSString stringWithFormat: @"X-WR-CALNAME:%@\r\n", calendarName];
	    
	[calendarFileString replaceCharactersInRange: calNameRange
			    withString: calNameString];
    }
    const char *responseDataBytes = [calendarFileString UTF8String];
    responseData = [NSData dataWithBytes: responseDataBytes length: strlen(responseDataBytes)];

    return [[[HTTPResponse alloc] initWithVersion: @"HTTP/1.0" status: 200
				  headers: [NSDictionary dictionaryWithObject: @"text/calendar" forKey: @"content-type"]
				  body: responseData] autorelease];
}

- (HTTPResponse*)responseForErrorStatus: (unsigned)status message: (NSString*)message
{
    NSString *errorPage
	= [NSString stringWithFormat: @"<html><head><title>Error %u</title></head><body><h1>%u</h1><p>%@</p></body></html>\n",
	      status, status, message];
    const char *errorPageData = [errorPage UTF8String];
    NSDictionary *headers = [NSDictionary dictionaryWithObjectsAndKeys:
				@"text/html; charset=utf-8",	@"content-type",
				@"close",			@"connection",
				nil];
    
    return [[[HTTPResponse alloc] initWithVersion: @"HTTP/1.0" status: status
	       headers: headers
	       body: [NSData dataWithBytes: errorPageData length: strlen(errorPageData)]] autorelease];
}

- (HTTPResponse*)responseForUnauthorizedRequest: (HTTPRequest*)request fromAddress: (NSString*)fromAddress stale: (BOOL)isStale
{
    const char *errorPageData = "<html><head><title>Error 401</title></head><body><h1>401</h1><p>This server requires a name and password.</p></body></html>\n";
    NSMutableDictionary *headers = [NSMutableDictionary dictionaryWithObjectsAndKeys:
				       @"text/html; charset=utf-8", @"content-type",
				       @"close",		    @"connection",
				       nil];
    
    // Add the WWW-Authenticate header
    if([[[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath: @"values.secDigestAuth"] boolValue])
    {
	ServerDigestClient *digestClient = [self newDigestClientForAddress: fromAddress];
	
	[headers setObject: [NSString stringWithFormat: @"Digest realm=\"%@\",qop=auth,nonce=\"%@\"%@",
							[m_passwordController realm], [digestClient nonce],
							(isStale? @",stale=true" : @"")]
		 forKey: @"www-authenticate"];
    }
    else
	[headers setObject: [NSString stringWithFormat: @"Basic realm=\"%@\"", [m_passwordController realm]]
		 forKey: @"www-authenticate"];

    return [[[HTTPResponse alloc] initWithVersion: @"HTTP/1.0" status: 401
	       headers: headers
	       body: [NSData dataWithBytes: errorPageData length: strlen(errorPageData)]] autorelease];    
}

- (BOOL)requestMatchesBasicCredentials: (HTTPRequest*)request
{
    NSString *auth = [[request valueForHeader: @"authorization"]
			 stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    // Verify this is a Basic auth
    if([[[auth substringWithRange: NSMakeRange(0, 6)] lowercaseString] isEqualToString: @"basic "])
    {
	const char *nullTerminator = "";
	// Un-base64 the credentials
	NSData *unencodedData = CalTalkServer_dataFromBase64String(
	    [[auth substringFromIndex: 6] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]]
	);
	if(!unencodedData)
	    return NO;
	NSMutableData *unencodedDataWithTerminator = [NSMutableData dataWithData: unencodedData];
	[unencodedDataWithTerminator appendBytes: nullTerminator length: 1];
	
	NSString *credentials = [NSString stringWithUTF8String: [unencodedDataWithTerminator bytes]];
	
	// Split the username:password pair
	NSRange colonRange = [credentials rangeOfString: @":"];
	NSString *userName = [credentials substringToIndex: colonRange.location];
	NSString *password = [credentials substringFromIndex: colonRange.location+1];
	
	return [userName isEqualToString: [m_passwordController userName]]
	       && [m_passwordController isPasswordCorrect: password];
    }
    else return NO;
}

- (BOOL)requestMatchesDigestCredentials: (HTTPRequest*)request fromAddress: (NSString*)fromAddress stale: (BOOL*)stale
{
    NSString *auth = [[request valueForHeader: @"authorization"]
			 stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    *stale = NO;
    // Verify this is a Digest auth
    if([[[auth substringWithRange: NSMakeRange(0, 7)] lowercaseString] isEqualToString: @"digest "])
    {
	// Parse the digest auth parameters
	// XXX should be a separate routine
	NSMutableDictionary *digestParams = [NSMutableDictionary dictionary];
	NSArray *digestParamsStrings = [[[auth substringFromIndex: 7]
					   stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]]
					   componentsSeparatedByString: @","];
	unsigned i, paramsLength = [digestParamsStrings count];
	for(i = 0; i < paramsLength; ++i)
	{
	    NSString *param = [digestParamsStrings objectAtIndex: i];
	    NSRange equalSignRange = [param rangeOfString: @"="];
	    if(equalSignRange.location == NSNotFound)
		return NO;
	    NSString *paramKey = [[[param substringToIndex: equalSignRange.location]
				     stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]]
				     lowercaseString],
		     *paramValue = [param substringFromIndex: equalSignRange.location+1],
		     *paramValueTrimmed = [paramValue stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	    
	    // Make sure quoted strings don't get divided
	    if([paramValueTrimmed characterAtIndex: 0] == '"')
	    {
		while(([paramValueTrimmed characterAtIndex: [paramValueTrimmed length]-1] != '"') && (++i < paramsLength))
		{
		    paramValue = [paramValue stringByAppendingFormat: @",%@", [digestParamsStrings objectAtIndex: i]];
		    paramValueTrimmed = [paramValue stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
		}
		paramValue = [paramValueTrimmed stringByTrimmingCharactersInSet:
				 [NSCharacterSet characterSetWithCharactersInString: @"\""]];
	    }
	    else
		paramValue = paramValueTrimmed;
	    [digestParams setObject: paramValue forKey: paramKey];
	}
	
	// Is the nonce stale?
	NSString *nonceFromRequest = [digestParams objectForKey: @"nonce"];
	if(!nonceFromRequest)
	    return NO;
	NSRange colonRange = [nonceFromRequest rangeOfString: @":"];
	if(colonRange.location == NSNotFound)
	    return NO;
	NSString *nonceIssueDateString = [nonceFromRequest substringToIndex: colonRange.location];
	NSDate *nonceIssueDate = [NSDate dateWithTimeIntervalSinceReferenceDate: [nonceIssueDateString doubleValue]];
	if([nonceIssueDate isGreaterThan: [NSDate date]]) // Can't be later than now
	    return NO;
	if(     [nonceIssueDate isLessThan: m_serverCreateDate]
	   || (-[nonceIssueDate timeIntervalSinceNow] > CALTALKSERVER_EXPIRE_DIGEST_CLIENT_SECONDS))
	{
	    *stale = YES;
	    return NO;
	}
	
	// Verify the client response
	ServerDigestClient *digestClient = [self digestClientForAddress: fromAddress];
	if(!digestClient)
	    return NO;
	
	NSString *requestCounterString = [digestParams objectForKey: @"nc"],
		 *serverNonce	       = [digestClient nonce],
		 *clientNonce          = [digestParams objectForKey: @"cnonce"],
		 *qop		       = [digestParams objectForKey: @"qop"],
		 *uri		       = [digestParams objectForKey: @"uri"],
		 *clientResponse       = [digestParams objectForKey: @"response"];
	if(!requestCounterString || !serverNonce || !clientNonce || !qop || !uri || !clientResponse)
	    return NO;
	if(![digestClient verifyAndSetNewRequestCount: [requestCounterString intValue]])
	    return NO;
	
	NSData *hash1 = [m_passwordController passwordHash],
	       *hash2 = CalTalk_md5HashDataForString([NSString stringWithFormat: @"%@:%@", [request method], uri]);
	NSString *responsePreHash = [NSString stringWithFormat: @"%@:%@:%@:%@:%@:%@",
								[hash1 hexRepresentation],
								serverNonce,
								requestCounterString,
								clientNonce,
								qop,
								[hash2 hexRepresentation]];
	NSData *responseHash = CalTalk_md5HashDataForString(responsePreHash);
	return [[responseHash hexRepresentation] isEqualToString: [clientResponse lowercaseString]];
    }
    else
	return NO;
}

- (void)listenSocketConnectionAcceptedNotification: (NSNotification*)notification
{
    NSFileHandle *connSocket = [[notification userInfo] objectForKey: @"NSFileHandleNotificationFileHandleItem"];
    
    [NSThread detachNewThreadSelector: @selector(readAndAnswerRequestFromFileHandle:) toTarget: self
	withObject: [connSocket retain]];
    
    // Accept another connection
    if(m_serverRunning)
	[m_listenSocket acceptConnectionInBackgroundAndNotify];
}

- (void)readAndAnswerRequestFromFileHandle: (NSFileHandle*)fileHandle
{
    NSAutoreleasePool *threadPool = [[NSAutoreleasePool alloc] init];
    NSMutableData *requestData = [NSMutableData data];
    NSData *readData;
    HTTPRequest *request;
    HTTPResponse *response;
    unsigned newlines = 0;
    NSString *clientAddress;
    
    // Get the client's address
    int fd = [fileHandle fileDescriptor];
    struct sockaddr_in clientSockAddr;
    socklen_t clientSockAddrLen = sizeof(clientSockAddr);
    if(getsockname(fd, (struct sockaddr*)&clientSockAddr, &clientSockAddrLen) == 0)
    {
	if(clientSockAddr.sin_family != AF_INET)
	    clientAddress = nil;
	else
	   @synchronized(g_calTalkController)
	   {
		const char *clientAddressCStr = inet_ntoa(clientSockAddr.sin_addr);
		clientAddress = [NSString stringWithUTF8String: clientAddressCStr];
	   } 
    }
    
    // Read in the headers
    for(;;)
    {
	readData = [fileHandle readDataOfLength: 1];
	if(!readData || [readData length] == 0)
	    break;
	
	// Skip over \rs
	if(*(const char*)[readData bytes] == '\r')
	    continue;
	
	[requestData appendData: readData];
	
	if(*(const char*)[readData bytes] == '\n')
	{
	    ++newlines;
	    if(newlines == 2)
		break;
	}
	else
	    newlines = 0;
    }
    request = [[HTTPRequest alloc] initWithData: requestData];
    
    // If a content-length is given, read in the body
    if(request && [request contentLength] > 0)
	[request setBody: [fileHandle readDataOfLength: [request contentLength]]];
    
    response = [self responseForRequest: request fromAddress: clientAddress];
    [request release];
    
    [fileHandle writeData: [response data]];
    [fileHandle closeFile];
    [fileHandle release];
    
    [threadPool release];
}

- (void)observeValueForKeyPath: (NSString*)keyPath ofObject: (id)object change: (NSDictionary*)change context: (void*)context
{
    id userDefaultsController = [NSUserDefaultsController sharedUserDefaultsController];
    if([object isEqual: userDefaultsController])
    {
	if([keyPath isEqualToString: @"values.shareName"] || [keyPath isEqualToString: @"values.sharePort"])
	{
	    NSString *newServerName = [userDefaultsController valueForKeyPath: @"values.shareName"];
	    unsigned short newPort = [[userDefaultsController valueForKeyPath: @"values.sharePort"] intValue];
	    BOOL changed = NO;

	    if(![newServerName isEqualToString: m_serverName])
	    {
		changed = YES;
		[m_serverName release];
		m_serverName = [newServerName retain];
	    }

	    if(newPort != m_port)
	    {
		changed = YES;
		m_port = newPort;
	    }

	    if(changed && m_serverRunning)
		[self restart];
	}
    }
	
    //[super observeValueForKeyPath: keyPath ofObject: object change: change context: context];
}

- (ServerDigestClient*)digestClientForAddress: (NSString*)address
{
    return [m_digestClients objectForKey: address];
}

- (ServerDigestClient*)newDigestClientForAddress: (NSString*)address
{
    ServerDigestClient *ret = [ServerDigestClient serverDigestClientForClientAddress: address];
    [m_digestClients setObject: ret forKey: address];
    return ret;
}

- (void)maintainDigestClients: (NSTimer*)timer
{
    NSEnumerator *digestClientEnumerator = [m_digestClients keyEnumerator];
    NSString *key;
    while((key = [digestClientEnumerator nextObject]))
    {
	NSDate *lastAccessDate = [[m_digestClients objectForKey: key] nonceLastAccessDate];
	if(-[lastAccessDate timeIntervalSinceNow] > CALTALKSERVER_KEEP_DIGEST_CLIENT_SECONDS)
	    [m_digestClients removeObjectForKey: key];
    }
}

- (void)startErrorAlertDidEnd: (NSAlert*)alert returnCode: (int)returnCode contextInfo: (void*)alternatePort
{
    if(returnCode == NSAlertFirstButtonReturn || returnCode == NSAlertDefaultReturn) // Try current port again
    {
	[NSTimer scheduledTimerWithTimeInterval: 0.001 target: self selector: @selector(startFromTimer:) userInfo: nil repeats: NO];
    }
    else if(returnCode == NSAlertSecondButtonReturn || returnCode == NSAlertAlternateReturn) // Stop sharing
    {
	[[NSUserDefaultsController sharedUserDefaultsController]
	    setValue: [NSNumber numberWithBool: NO] forKeyPath: @"values.shareCalendars"];
    }
    else if(returnCode == NSAlertThirdButtonReturn || returnCode == NSAlertOtherReturn) // Try another port
    {
	m_port = (unsigned short)alternatePort;
	[[NSUserDefaultsController sharedUserDefaultsController]
	    setValue: [NSNumber numberWithUnsignedShort: m_port] forKeyPath: @"values.sharePort"];
	[NSTimer scheduledTimerWithTimeInterval: 0.001 target: self selector: @selector(startFromTimer:) userInfo: nil repeats: NO];
    }
}

@end

#pragma mark -

static const char *CALTALKSERVER_BASE64_SET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

NSData *
CalTalkServer_dataFromBase64String(NSString *base64String)
{
    unsigned char sextets[4], octets[3];
    unsigned int stringLength = [base64String length], i, j;
    unsigned int numberOfRemainders = stringLength - ([base64String rangeOfString: @"="]).location;
    NSMutableData *returnData = [NSMutableData dataWithCapacity: stringLength * 3/4 + 1];
    BOOL ending = NO;
    
    for(i = 0; i < stringLength; i += 4)
    {
	for(j = 0; (j < 4) && (i+j < stringLength); ++j)
	{
	    unichar c = [base64String characterAtIndex: i+j];
	    if(c == '=')
	    {
		ending = YES;
		break;
	    }
	    const char *charPos = strchr(CALTALKSERVER_BASE64_SET, c);
	    if(!charPos)
		return nil;
	    sextets[j] = charPos - CALTALKSERVER_BASE64_SET;
	}
	for(; j < 4; ++j) sextets[j] = 0;
	octets[0] = (sextets[0] << 2) | (sextets[1] >> 4);
	octets[1] = ((sextets[1] & 0xf) << 4) | (sextets[2] >> 2);
	octets[2] = ((sextets[2] & 0x3) << 6) | sextets[3];
	
	[returnData appendBytes: octets length: 3 - (ending? numberOfRemainders : 0)];
    }
    return returnData;
}