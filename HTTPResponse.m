//
//  HTTPResponse.m
//  CalTalk
//

#import "HTTPResponse.h"
#include <stdlib.h>

static NSDictionary *HTTP_statusStrings;

@implementation HTTPResponse

+ (void)initialize
{
    HTTP_statusStrings = [[NSDictionary alloc] initWithObjectsAndKeys:
	@"Continue",			[NSNumber numberWithUnsignedInt: 100],
	@"Switching protocols",		[NSNumber numberWithUnsignedInt: 101],
	@"Processing",			[NSNumber numberWithUnsignedInt: 102],
	@"OK",				[NSNumber numberWithUnsignedInt: 200],
	@"Created",			[NSNumber numberWithUnsignedInt: 201],
	@"Accepted",			[NSNumber numberWithUnsignedInt: 202],
	@"Non-authoritative",		[NSNumber numberWithUnsignedInt: 203],
	@"No content",			[NSNumber numberWithUnsignedInt: 204],
	@"Reset content",		[NSNumber numberWithUnsignedInt: 205],
	@"Partial content",		[NSNumber numberWithUnsignedInt: 206],
	@"Multiple choices",		[NSNumber numberWithUnsignedInt: 300],
	@"Moved permanently",		[NSNumber numberWithUnsignedInt: 301],
	@"Moved temporarily",		[NSNumber numberWithUnsignedInt: 302],
	@"See other",			[NSNumber numberWithUnsignedInt: 303],
	@"Not modified",		[NSNumber numberWithUnsignedInt: 304],
	@"Use proxy",			[NSNumber numberWithUnsignedInt: 305],
	@"Bad request",			[NSNumber numberWithUnsignedInt: 400],
	@"Unauthorized",		[NSNumber numberWithUnsignedInt: 401],
	@"Payment required",		[NSNumber numberWithUnsignedInt: 402],
	@"Forbidden",			[NSNumber numberWithUnsignedInt: 403],
	@"Not found",			[NSNumber numberWithUnsignedInt: 404],
	@"Method not allowed",		[NSNumber numberWithUnsignedInt: 405],
	@"Not acceptable",		[NSNumber numberWithUnsignedInt: 406],
	@"Proxy authentication required",   [NSNumber numberWithUnsignedInt: 407],
	@"Request timeout",		[NSNumber numberWithUnsignedInt: 408],
	@"Conflict",			[NSNumber numberWithUnsignedInt: 409],
	@"Gone",			[NSNumber numberWithUnsignedInt: 410],
	@"Length required",		[NSNumber numberWithUnsignedInt: 411],
	@"Precondition failed",		[NSNumber numberWithUnsignedInt: 412],
	@"Request entity too large",	[NSNumber numberWithUnsignedInt: 413],
	@"Request URL too long",	[NSNumber numberWithUnsignedInt: 414],
	@"Unsupported media type",	[NSNumber numberWithUnsignedInt: 415],
	@"Internal server error",	[NSNumber numberWithUnsignedInt: 500],
	@"Not implemented",		[NSNumber numberWithUnsignedInt: 501],
	@"Bad gateway",			[NSNumber numberWithUnsignedInt: 502],
	@"Service unavailable",		[NSNumber numberWithUnsignedInt: 503],
	@"Gateway timeout",		[NSNumber numberWithUnsignedInt: 504],
	@"HTTP version unsupported",	[NSNumber numberWithUnsignedInt: 505],
	nil];
}

- initWithFirstLine: (NSString*)firstLine headers: (NSDictionary*)headers body: (NSData*)body
{
    self = [super initWithFirstLine: firstLine headers: headers body: body];
    if(self)
    {
	// Parse the first line
	NSRange firstWordEnd = [firstLine rangeOfCharacterFromSet: [NSCharacterSet whitespaceCharacterSet]];
	NSRange versionRange, statusRange;
	if(firstWordEnd.location == NSNotFound || [firstLine length] < (firstWordEnd.location + 3))
	{
	    [self release];
	    return nil;
	}
	versionRange.location = 0;
	versionRange.length = firstWordEnd.location;
	statusRange.location = firstWordEnd.location + 1;
	statusRange.length = 3;
	
	m_version = [[[firstLine substringWithRange: versionRange] uppercaseString] retain];
	m_status = atoi([[firstLine substringWithRange: statusRange] UTF8String]);
    }
    return self;
}

- initWithVersion: (NSString*)version status: (unsigned)status headers: (NSDictionary*)headers body: (NSData*)body
{
    NSString *versionStr = [version uppercaseString],
             *firstLine  = [NSString stringWithFormat: @"%@ %u %@", versionStr, status,
			       [HTTP_statusStrings objectForKey: [NSNumber numberWithUnsignedInt: status]]];
    
    self = [super initWithFirstLine: firstLine headers: headers body: body];
    if(self)
    {
	m_version = [versionStr retain];
	m_status = status;
    }
    return self;
}

- (void)dealloc
{
    [m_version release];
    [super dealloc];
}

- (NSString*)version
{
    return m_version;
}

- (unsigned)status
{
    return m_status;
}

@end
