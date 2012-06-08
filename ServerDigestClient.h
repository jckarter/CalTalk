//
//  ServerDigestClient.h
//  CalTalk
//
//  Simple class in which to cache nonces and request counts for HTTP digest auth clients

#import <Cocoa/Cocoa.h>

@interface ServerDigestClient : NSObject
{
    NSString *m_clientAddress;
    NSDate *m_nonceIssueDate, *m_nonceLastAccessDate;
    
@private
    unsigned m_requestCount;
    unsigned long long m_nonceSalt;
}

// Designated initializer
- initForClientAddress: (NSString*)clientAddress;
+ (ServerDigestClient*)serverDigestClientForClientAddress: (NSString*)clientAddress;

// Get the nonce value for this client
- (NSString*)nonce;

// Get the issue date and last access date for this nonce
- (NSDate*)nonceIssueDate;
- (NSDate*)nonceLastAccessDate;

// Check the given request count and set ours if it is greater than the current request count. Returns YES if
// the new request count is valid.
- (BOOL)verifyAndSetNewRequestCount: (unsigned)requestCount;

@end
