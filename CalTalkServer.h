//
//  HTTPServer.h
//  CalTalk
//

#import <Cocoa/Cocoa.h>
#import "HTTPRequest.h"
#import "HTTPResponse.h"

@class CalTalkController;
@class PasswordController;

@interface CalTalkServer : NSObject
{
    NSDate *m_serverCreateDate;
    NSFileHandle *m_listenSocket;
    NSNetService *m_netService;
    
    CalTalkController *m_calTalkController;
    PasswordController *m_passwordController;
    
    NSString *m_serverName;
    unsigned short m_port;
    unsigned m_serverNameNumber;    // Number added to server name to make it unique, when more than one computer
				    // on the network has the same name
    
    NSMutableDictionary *m_digestClients;
    NSTimer *m_maintainDigestClientsTimer;
    
    BOOL m_serverRunning, m_serverPublished;
}

// Designated initializer. Initialize the server to serve calendars managed by the given CalTalkController
// object.
- initWithController: (CalTalkController*)controller;

// Get the Rendezvous name and listening port of the server
- (NSString*)serverName;
- (unsigned)port;
// Get the NSNetService object representing the Rendezvous service
- (NSNetService*)netService;

// Return YES if server is accepting requests
- (BOOL)serverRunning;
// Return YES if the server is being published through Rendezvous
- (BOOL)serverPublished;

// Start, stop, and restart the server
- (void)start;
- (void)stop;
- (void)restart;

@end
