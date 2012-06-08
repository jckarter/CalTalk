//
//  HTTPResponse.h
//  CalTalk
//
//  A response to an HTTP request.
//

#import <Cocoa/Cocoa.h>
#import "HTTPMessage.h"


@interface HTTPResponse : HTTPMessage
{
    NSString *m_version;
    unsigned m_status;
}

// Initialize with the given version, status, headers, and body
- initWithVersion: (NSString*)version status: (unsigned)status headers: (NSDictionary*)headers body: (NSData*)body;

- (void)dealloc;

// Access version and status
- (NSString*)version;
- (unsigned)status;

@end
