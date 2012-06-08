//
//  HTTPRequest.h
//  CalTalk
//
//  A request from an HTTP client
//

#import <Cocoa/Cocoa.h>
#import "HTTPMessage.h"


@interface HTTPRequest : HTTPMessage
{
    NSString *m_method, *m_path, *m_version;
}

// Initialize with the specified method, path, HTTP version, headers, and body
- initWithMethod: (NSString*)method path: (NSString*)path version: (NSString*)version
    headers: (NSDictionary*)headers body: (NSData*)body;

- (void)dealloc;

// Get the request method, path, and version
- (NSString*)method;
- (NSString*)path;
- (NSString*)version;

@end
