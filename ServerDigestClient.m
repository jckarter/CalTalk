//
//  ServerDigestClient.m
//  CalTalk
//

#import "NSData_HexRepresentation.h"
#import "ServerDigestClient.h"
#import "CalTalk.h"
#import <stdlib.h>

@interface ServerDigestClient (Private)

- (void)updateNonceLastAccessDate;

@end

#pragma mark -

@implementation ServerDigestClient

- initForClientAddress: (NSString*)clientAddress
{
    self = [super init];
    if(self)
    {
	m_clientAddress = [clientAddress retain];
	m_nonceIssueDate = [[NSDate alloc] init];
	m_nonceLastAccessDate = [m_nonceIssueDate retain];
	m_requestCount = 0;
	srandomdev();
	m_nonceSalt = ((unsigned long long)random() << 32) | random();
    }
    return self;
}

+ (ServerDigestClient*)serverDigestClientForClientAddress: (NSString*)clientAddress
{
    return [[[self alloc] initForClientAddress: clientAddress] autorelease];
}

- (NSString*)nonce
{
    [self updateNonceLastAccessDate];
    
    NSData *nonceHash = CalTalk_md5HashDataForString(
	[NSString stringWithFormat: @"%@:%@:%u", m_clientAddress, m_nonceIssueDate, m_nonceSalt]
    );
    return [NSString stringWithFormat: @"%lld:%@",
		         (long long)[m_nonceIssueDate timeIntervalSinceReferenceDate], [nonceHash hexRepresentation]];
}

- (NSDate*)nonceIssueDate
{
    return m_nonceIssueDate;
}

- (NSDate*)nonceLastAccessDate
{
    return m_nonceLastAccessDate;
}

- (BOOL)verifyAndSetNewRequestCount: (unsigned)requestCount
{
    if(requestCount > m_requestCount)
    {
	m_requestCount = requestCount;
	return YES;
    }
    else
	return NO;
}

@end

#pragma mark -

@implementation ServerDigestClient (Private)

- (void)updateNonceLastAccessDate
{
    NSDate *oldLastAccessDate = m_nonceLastAccessDate;
    m_nonceLastAccessDate = [[NSDate alloc] init];
    [oldLastAccessDate release];
}

@end
