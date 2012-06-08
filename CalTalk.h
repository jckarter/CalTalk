//
//  CalTalk.h
//  Definitions common to all CalTalk stuff
//

// The default port to listen for connections on 
#define CALTALK_DEFAULT_SHARE_PORT  28080
// The Rendezvous service type to broadcast
#define CALTALK_SERVICE_TYPE  @"_caltalk._tcp."
// The folder in which calendars are kept
#define CALTALK_CALENDAR_FOLDER_1_X @"~/Library/Calendars"
#define CALTALK_CALENDAR_FOLDER_2_X @"~/Library/Application Support/iCal/Sources"

// The global controller object
@class CalTalkController;
extern CalTalkController *g_calTalkController;

// Generate an MD5 hash of the given string (defined in PasswordController.h)
NSData *CalTalk_md5HashDataForString(NSString *string);