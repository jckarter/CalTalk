//
//  HTTPRequest.m
//  CalTalk
//

#import "HTTPRequest.h"


@implementation HTTPRequest

- initWithFirstLine: (NSString*)firstLine headers: (NSDictionary*)headers body: (NSData*)body
{
    self = [super initWithFirstLine: firstLine headers: headers body: body];
    if(self)
    {
	// Parse the first line
	NSRange firstWordEnd = [firstLine rangeOfCharacterFromSet: [NSCharacterSet whitespaceCharacterSet]];
	NSRange lastWordBegin = [firstLine rangeOfCharacterFromSet: [NSCharacterSet whitespaceCharacterSet]
				    options: NSBackwardsSearch];
	NSRange methodRange, pathRange, versionRange;
	if(firstWordEnd.location == NSNotFound || lastWordBegin.location == NSNotFound
	   || firstWordEnd.location == lastWordBegin.location)
	{
	    [self release];
	    return nil;
	}
	methodRange.location = 0;
	methodRange.length = firstWordEnd.location;
	versionRange.location = lastWordBegin.location + 1;
	versionRange.length = [firstLine length] - versionRange.location;
	pathRange.location = firstWordEnd.location + 1;
	pathRange.length = (lastWordBegin.location - firstWordEnd.location) - 1;
	
	m_method = [[[firstLine substringWithRange: methodRange] uppercaseString] retain];
	m_path = [[[[firstLine substringWithRange: pathRange]
		     stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]]
		     stringByReplacingPercentEscapesUsingEncoding: NSUTF8StringEncoding] retain];
	m_version = [[[firstLine substringWithRange: versionRange] uppercaseString] retain];
    }
    return self;
}

- initWithMethod: (NSString*)method path: (NSString*)path version: (NSString*)version
    headers: (NSDictionary*)headers body: (NSData*)body
{
    NSString *methodStr  = [method uppercaseString],
	     *pathStr    = [path stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding],
	     *versionStr = [version uppercaseString],
             *firstLine  = [NSString stringWithFormat: @"%@ %@ %@", methodStr, pathStr, versionStr];
    
    self = [super initWithFirstLine: firstLine headers: headers body: body];
    if(self)
    {
	m_method  = [methodStr retain];
	m_path    = [pathStr retain];
	m_version = [versionStr retain];
    }
    return self;
}

- (void)dealloc
{
    [m_method release];
    [m_path release];
    [m_version release];
    [super dealloc];
}

- (NSString*)method
{
    return m_method;
}

- (NSString*)path
{
    return m_path;
}

- (NSString*)version
{
    return m_version;
}

@end
