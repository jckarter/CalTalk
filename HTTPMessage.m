#import "HTTPMessage.h"
#include <ctype.h>
#include <string.h>
#include <stdlib.h>

@implementation HTTPMessage

- initWithFirstLine: (NSString*)firstLine headers: (NSDictionary*)headers body: (NSData*)body
{
    self = [super init];
    if(self)
    {
	m_firstLine = [firstLine retain];
	m_headers = [[NSMutableDictionary alloc] initWithDictionary: headers];
	m_body = [body retain];
	// If no content-length was given, set one
	if(m_body && ![m_headers objectForKey: @"content-length"])
	{
	    [m_headers setObject: [NSString stringWithFormat: @"%u", [m_body length]] forKey: @"content-length"];
	}
    }
    return self;
}

- initWithData: (NSData*)data
{
    const char *dataStart, *dataNewline, *dataColon;
    size_t dataLen;
    NSString *firstLine = nil, *headerName = nil, *headerValue = nil;
    NSMutableDictionary *headers = nil;
    NSData *body = nil;
    
    dataStart = (const char*) [data bytes];
    dataLen = [data length];
    
    // Read the first line
    dataNewline = memchr(dataStart, '\n', dataLen);
    if(!dataNewline)
	goto initWithData_error;
    firstLine = [NSString stringWithCString: dataStart length: dataNewline - dataStart];
    
    // Read the headers
    headers = [NSMutableDictionary dictionary];
    for(;;)
    {
	dataLen -= (dataNewline - dataStart + 1);
	// Shouldn't reach the end before reading all the headers
	if(dataLen <= 0)
	    goto initWithData_error;
	dataStart = ++dataNewline;
	// Break when we get an empty line
	if(*dataStart == '\n')
	    break;
	    
	dataNewline = memchr(dataStart, '\n', dataLen);
	if(!dataNewline)
	    goto initWithData_error;
	dataColon   = memchr(dataStart,  ':', dataNewline - dataStart);
	if(!dataColon)
	    goto initWithData_error;
	
	headerName = [NSString stringWithCString: dataStart length: dataColon - dataStart];
	do { ++dataColon; } while(*dataColon == ' ' || *dataColon == '\t');
	headerValue = [NSString stringWithCString: dataColon length: dataNewline - dataColon];
	
	[headers setObject: headerValue forKey: [headerName lowercaseString]];
    }
    
    // The remainder, if any, is the body
    if(dataLen > 1)
    {
	body = [NSData dataWithBytes: ++dataStart length: --dataLen];
	// Make a content-length header if needed
	if(![headers objectForKey: @"content-length"])
	    [headers setObject: [NSString stringWithFormat: @"%u", [body length]] forKey: @"content-length"];
    }
    else
    {
	// Body will need to be added later
	body = nil;
    }
    
    return self = [self initWithFirstLine: firstLine headers: headers body: body];
initWithData_error:
    [self release];
    return nil;
}

- (void)dealloc
{
    [m_firstLine release];
    [m_headers release];
    [m_body release];
    [super dealloc];
}

- (NSString*)firstLine
{
    return m_firstLine;
}

- (NSData*)body
{
    return m_body;
}

- (void)setBody: (NSData*)newBody
{
    NSData *oldBody = m_body;
    m_body = [newBody retain];
    [oldBody release];
    
    // If a content-length isn't already given, set it
    if(![m_headers objectForKey: @"content-length"])
	[m_headers setObject: [NSString stringWithFormat: @"%u", [newBody length]] forKey: @"content-length"];
}

- (NSString*)valueForHeader: (NSString*)header
{
    id value = [m_headers objectForKey: [header lowercaseString]];
    if([value isEqual: [NSNull null]])
	return nil;
    return value;
}

- (unsigned)contentLength
{
    NSString *contentLengthStr = [m_headers objectForKey: @"content-length"];
    if(contentLengthStr)
	return atoi([contentLengthStr UTF8String]);
    else
	return 0;
}

- (NSEnumerator*)headerEnumerator
{
    return [m_headers keyEnumerator];
}

- (id)valueForUndefinedKey: (NSString*)key
{
    return [m_headers valueForKey: key];
}

- (NSData*)data
{
    NSMutableString *headerString = [NSMutableString string];
    NSEnumerator *headerEnum = [m_headers keyEnumerator];
    NSString *headerKey;
    char *rawData;
    const char *headerRawString;
    size_t rawDataLen, headerRawStringLen;
    
    [headerString appendFormat: @"%@\r\n", m_firstLine];
    while(headerKey = [headerEnum nextObject])
    {
	[headerString appendFormat: @"%@: %@\r\n", headerKey, [m_headers objectForKey: headerKey]];
    }
    [headerString appendString: @"\r\n"];
    headerRawString = [headerString UTF8String];
    headerRawStringLen = strlen(headerRawString);

    rawDataLen = headerRawStringLen + [m_body length];
    rawData = malloc(rawDataLen);
    memcpy(rawData, headerRawString, headerRawStringLen);
    [m_body getBytes: (rawData + headerRawStringLen)];
    
    return [NSData dataWithBytesNoCopy: rawData length: rawDataLen freeWhenDone: YES];
}

@end
