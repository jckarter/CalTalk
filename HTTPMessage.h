//
//  HTTPMessage.h
//
//  Parse and generate HTTP-style requests and responses, consisting of a series of "Name: Value" pairs
//  followed by a blank line and a body of arbitrary binary data.
//

#import <Cocoa/Cocoa.h>


@interface HTTPMessage : NSObject
{
    NSString *m_firstLine;
    NSMutableDictionary *m_headers;
    NSData *m_body;
}

// Designated initializer. Initialize the message with a pre-parsed first line, body, and set of headers.
// The keys of the headers dictionary must all be lowercase strings.
- initWithFirstLine: (NSString*)firstLine headers: (NSDictionary*)headers body: (NSData*)body;

// Initialize the message from its canonical representation as an NSData object
- initWithData: (NSData*)data;

// Release retained objects
- (void)dealloc;

// Access the first line, header dictionary, and body
- (NSString*)firstLine;
- (NSData*)body;

// Add body data that was read after the headers
- (void)setBody: (NSData*)newBody;

// Get the value of a particular header
- (NSString*)valueForHeader: (NSString*)header;

// Value of the Content-Length: header, or 0 if none is present
- (unsigned)contentLength;

// Return an enumerator to go through all the headers in a request
- (NSEnumerator*)headerEnumerator;

// Look up unknown keys in the header dictionary
- (id)valueForUndefinedKey: (NSString*)key;

// Write the message out in its canonical form as an NSData object
- (NSData*)data;

@end
