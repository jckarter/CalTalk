/* CalTalkData */

#import <Cocoa/Cocoa.h>
#import "UKKQueue.h"

@interface CalTalkData : NSObject
{
    UKKQueue *m_kqueue;
    NSNetServiceBrowser *m_calTalkBrowser;
    NSMutableArray *m_networkUsers;
    NSMutableArray *m_myCalendars;
    NSMutableArray *m_progress;
}

// Return an array containing the names and states of the user's calendars. Each element of the array
// is a SharedCalendarData object, which is KVC-compliant for the following keys:
//   (ro) calendarName     - an NSString holding the name of the calendar.
//   (ro) calendarFileName - an NSString holding the path to the file with information on this calendar.
//   (rw) calendarShared   - an NSNumber holding a boolean value indicating whether the calendar is being shared.
- (NSArray*)myCalendars;

// Return an array containing the names of all the users currently sharing calendars on the network. Each
// element of the array is a NetworkUserData object, which is KVC-compliant for the following keys:
//   (ro) userName        - an NSString holding the user's name.
//   (ro) userService     - an NSNetService object representing the user's network service.
//   (ro) sharedCalendars - An NSArray of NSStrings containing the names of the user's shared calendars.
- (NSArray*)networkUsers;

// Return YES if some sort of job is in progress, NO if none are.
- (BOOL)workInProgress;
// Add a job to the progress list. The progress indicator will spin while at least one job is on the list.
- (void)addJobToProgress: (NSString*)jobName;
// Remove a job from the progress list.
- (void)removeJobFromProgress: (NSString*)jobName;

@end
