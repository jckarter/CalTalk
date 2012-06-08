#import "CalTalk.h"
#import "CalTalkController.h"
#import "CalTalkData.h"
#import "CalTalkServer.h"
#import "SharedCalendarData.h"
#import "NetworkUserData.h"

static NSArray *CalTalkData_getLocalCalendars_1_x(void);
static NSArray *CalTalkData_getLocalCalendars_2_x(void);

@interface CalTalkData (Private)

// Populate the list of calendars
- (void)populateMyCalendars;

// Delegate methods for the NSNetServiceBrowser
- (void)netServiceBrowser: (NSNetServiceBrowser*)browser didFindService: (NSNetService*)aService
      moreComing: (BOOL)moreComing;
- (void)netServiceBrowser: (NSNetServiceBrowser*)browser didRemoveService: (NSNetService*)aService
      moreComing: (BOOL)moreComing;
- (void)netServiceBrowser: (NSNetServiceBrowser*)aBrowser didNotSearch: (NSDictionary*)errorDict;

// KVC accessors for array properties
- (unsigned)countOfMyCalendars;
- (SharedCalendarData*)objectInMyCalendarsAtIndex: (unsigned)index;

- (unsigned)countOfNetworkUsers;
- (NetworkUserData*)objectInNetworkUsersAtIndex: (unsigned)index;

// UKKQueue delegate methods
- (void)kqueue: (UKKQueue*)kq receivedNotification: (NSString*)nm forFile: (NSString*)fpath;

@end

#pragma mark -

@implementation CalTalkData

// No automatic KVO notifications
+ (BOOL)automaticallyNotifiesObserversForKey: (NSString*)key
{
    return NO;
}

- init
{
    self = [super init];
    if(self)
    {
	m_networkUsers = [[NSMutableArray alloc] init];
	m_myCalendars = [[NSMutableArray alloc] init];
	m_progress = [[NSMutableArray alloc] init];
	m_calTalkBrowser = [[NSNetServiceBrowser alloc] init];

	[self populateMyCalendars];
	m_kqueue = [[UKKQueue alloc] init];
	[m_kqueue setDelegate: self];
	[m_kqueue addPathToQueue: [CALTALK_CALENDAR_FOLDER_1_X stringByExpandingTildeInPath]];
	[m_kqueue addPathToQueue: [CALTALK_CALENDAR_FOLDER_2_X stringByExpandingTildeInPath]];

	[m_calTalkBrowser setDelegate: self];
	[m_calTalkBrowser searchForServicesOfType: CALTALK_SERVICE_TYPE inDomain: @""];
    }
    return self;
}

- (void)dealloc
{
    [m_kqueue release];
    [m_calTalkBrowser stop];
    [m_calTalkBrowser release];
    [m_myCalendars release];
    [m_networkUsers release];
    
    [super dealloc];
}

- (NSArray*)myCalendars
{
    return m_myCalendars;
}

- (NSArray*)networkUsers
{
    return m_networkUsers;
}

- (BOOL)workInProgress
{
	return ([m_progress count] > 0)? YES : NO;
}

- (void)addJobToProgress: (NSString*)jobName
{
	BOOL changing;
	if([m_progress indexOfObject: jobName] == NSNotFound)
	{
	    changing = ([m_progress count] == 0);
	    if(changing)
		[self willChangeValueForKey: @"workInProgress"];
	    [m_progress addObject: jobName];
	    if(changing)
		[self didChangeValueForKey: @"workInProgress"];
	}
}

- (void)removeJobFromProgress: (NSString*)jobName
{
	BOOL changing;
	unsigned jobIndex = [m_progress indexOfObject: jobName];
	if(jobIndex != NSNotFound)
	{
	    changing = ([m_progress count] == 1);
	    if(changing)
		[self willChangeValueForKey: @"workInProgress"];
	    [m_progress removeObjectAtIndex: jobIndex];
	    if(changing)
		[self didChangeValueForKey: @"workInProgress"];
	}
}

@end

#pragma mark -

@implementation CalTalkData (Private)

- (void)populateMyCalendars
{
    NSArray *localCalendars;
    NSEnumerator *localCalendarsEnum;
    SharedCalendarData *calendar;

    localCalendars = CalTalkData_getLocalCalendars_2_x();
    if(!localCalendars)
	    localCalendars = CalTalkData_getLocalCalendars_1_x();
    if(!localCalendars)
    {
	    // XXX should quit app on this condition
	    NSLog(@"No calendars found!\n");
	    return;
    }

    /* See which calendars are new and which have been removed */
    NSMutableArray *addCalendars = [NSMutableArray arrayWithCapacity: [localCalendars count]],
		   *delCalendars = [NSMutableArray arrayWithArray: m_myCalendars];
    localCalendarsEnum = [localCalendars objectEnumerator];
    while(calendar = [localCalendarsEnum nextObject])
    {
	if([delCalendars indexOfObject: calendar] != NSNotFound)
	    [delCalendars removeObject: calendar];
	else
	    [addCalendars addObject: calendar];
    }
    
    if([delCalendars count] > 0)
    {
		NSEnumerator *delEnum = [delCalendars objectEnumerator];
		id delObj;
		unsigned delIndex;
		
		while(delObj = [delEnum nextObject])
		{
			delIndex = [m_myCalendars indexOfObject: delObj];
			[self willChange: NSKeyValueChangeRemoval valuesAtIndexes: [NSIndexSet indexSetWithIndex: delIndex]
			  forKey: @"myCalendars"];
			[[m_myCalendars objectAtIndex: delIndex] removeFromDefaults];
			[m_myCalendars removeObjectAtIndex: delIndex];
			[self didChange: NSKeyValueChangeRemoval valuesAtIndexes: [NSIndexSet indexSetWithIndex: delIndex]
			  forKey: @"myCalendars"];
		}
    }
    
    if([addCalendars count] > 0)
    {
		NSRange addRange = { [m_myCalendars count], [addCalendars count] };
		[self willChange: NSKeyValueChangeInsertion
			  valuesAtIndexes: [NSIndexSet indexSetWithIndexesInRange: addRange]
			  forKey: @"myCalendars"];
		[m_myCalendars addObjectsFromArray: addCalendars];
		[self didChange: NSKeyValueChangeInsertion
			  valuesAtIndexes: [NSIndexSet indexSetWithIndexesInRange: addRange]
			  forKey: @"myCalendars"];
    }
}

- (void)netServiceBrowser: (NSNetServiceBrowser*)browser didFindService: (NSNetService*)newService
      moreComing: (BOOL)moreComing
{
    NSIndexSet *addedIndexSet = [NSIndexSet indexSetWithIndex: [m_networkUsers count]];

    // Ignore ourselves
    NSNetService *ourService = [[g_calTalkController server] netService];
    if([newService isEqual: ourService])
	return;

    [self willChange: NSKeyValueChangeInsertion
	  valuesAtIndexes: addedIndexSet forKey: @"networkUsers"];
    [m_networkUsers addObject: [NetworkUserData userDataWithNetService: newService]];
    [self didChange: NSKeyValueChangeInsertion
	  valuesAtIndexes: addedIndexSet forKey: @"networkUsers"];
}

- (void)netServiceBrowser: (NSNetServiceBrowser*)browser didRemoveService: (NSNetService*)lostService
      moreComing: (BOOL)moreComing
{
    unsigned removedIndex = [m_networkUsers indexOfObject:
				[NetworkUserData userDataWithNetService: lostService refreshSharedCalendars: NO]];

    // Ignore ourselves
    NSNetService *ourService = [[g_calTalkController server] netService];
    if([lostService isEqual: ourService])
 	return;

    if(removedIndex != NSNotFound)
    {
	NSIndexSet *removedIndexSet = [NSIndexSet indexSetWithIndex: removedIndex];
	[self willChange: NSKeyValueChangeRemoval valuesAtIndexes: removedIndexSet forKey: @"networkUsers"];
	[m_networkUsers removeObjectAtIndex: removedIndex];
	[self didChange: NSKeyValueChangeInsertion valuesAtIndexes: removedIndexSet forKey: @"networkUsers"];
    }
}

- (void)netServiceBrowser: (NSNetServiceBrowser*)browser didNotSearch: (NSDictionary*)errorDict
{
    // XXX handle error condition
}

- (unsigned)countOfMyCalendars
{
    return [m_myCalendars count];
}

- (SharedCalendarData*)objectInMyCalendarsAtIndex: (unsigned)index
{
    return [m_myCalendars objectAtIndex: index];
}

- (unsigned)countOfNetworkUsers
{
    return [m_networkUsers count];
}

- (NetworkUserData*)objectInNetworkUsersAtIndex: (unsigned)index
{
    return [m_networkUsers objectAtIndex: index];
}

- (void)kqueue: (UKKQueue*)kq receivedNotification: (NSString*)nm forFile: (NSString*)fpath
{
	// Repopulate the list. Naive, but gets the job done
	[self populateMyCalendars];
}

@end

/* Get the local calendar files from iCal 1.x (Panther). Easy--iCal keeps all the calendars
 * in ~/Library/Calendars with filenames matching the calendar name. */
static NSArray *
CalTalkData_getLocalCalendars_1_x(void)
{
    NSString *calendarsFolder = [CALTALK_CALENDAR_FOLDER_1_X stringByExpandingTildeInPath];
    NSArray *dirContents = [[NSFileManager defaultManager] directoryContentsAtPath: calendarsFolder];
    NSEnumerator *dirContentsEnum;
    NSString *dirContentsFile;
    NSMutableArray *calendarDataArray = nil;
    
    if(dirContents && [dirContents count] > 0)
    {
	calendarDataArray = [NSMutableArray arrayWithCapacity: [dirContents count]];
	dirContentsEnum = [dirContents objectEnumerator];
	while(dirContentsFile = [dirContentsEnum nextObject])
	{
	    if(![[dirContentsFile pathExtension] isEqualToString: @"ics"])
		continue;
	    [calendarDataArray addObject:
		[SharedCalendarData calendarDataWithCalendarName: [dirContentsFile stringByDeletingPathExtension]
				    calendarFileName: [NSString stringWithFormat: @"%@/%@", calendarsFolder, dirContentsFile]]];
	}
	if([calendarDataArray count] == 0)
	    calendarDataArray = nil;
    }
    
    return calendarDataArray;
}

/* Get the local calendar files from iCal 2.x (Tiger). Harder--iCal 2 keeps a bunch of
 * .calendar folders in ~/Library/Application Support/iCal/Sources with GUIDs for names
 * corresponding to every calendar in the user's list. We need to
 * extract the calendar names from the Info.plist in each folder. */
static NSArray *
CalTalkData_getLocalCalendars_2_x(void)
{
    NSString *calendarsFolder = [CALTALK_CALENDAR_FOLDER_2_X stringByExpandingTildeInPath];
    NSArray *dirContents = [[NSFileManager defaultManager] directoryContentsAtPath: calendarsFolder];
    NSEnumerator *dirContentsEnum;
    NSString *dirContentsFolder;
    NSDictionary *calPlist;
    NSMutableArray *calendarDataArray = nil;
    
    if(dirContents && [dirContents count] > 0)
    {
	calendarDataArray = [NSMutableArray arrayWithCapacity: [dirContents count]];
	dirContentsEnum = [dirContents objectEnumerator];
	while(dirContentsFolder = [dirContentsEnum nextObject])
	{
	    if(![[dirContentsFolder pathExtension] isEqualToString: @"calendar"])
		continue;
	    calPlist = [NSDictionary dictionaryWithContentsOfFile:
			   [NSString stringWithFormat: @"%@/%@/Info.plist", calendarsFolder, dirContentsFolder]];
	    if(!calPlist)
		continue;
	    
	    // The "Birthdays" calendar doesn't have a title
	    NSString *title = [calPlist objectForKey: @"Title"];
	    if(title == nil || [@"" isEqualToString: title])
		//XXX: support Birthdays calendar
		//title = NSLocalizedString(@"Birthdays", @"");
		continue;
	    
	    //if(![[calPlist objectForKey: @"Type"] isEqualToString: @"com.apple.ical.sources.naivereadwrite"])
	    //	continue;
	    [calendarDataArray addObject:
		    [SharedCalendarData calendarDataWithCalendarName: title
					calendarFileName: [NSString stringWithFormat: @"%@/%@/corestorage.ics", calendarsFolder, dirContentsFolder]]];
	}
	if([calendarDataArray count] == 0)
	    calendarDataArray = nil;
    }
    
    return calendarDataArray;
}