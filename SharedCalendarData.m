//
//  SharedCalendarData.m
//  CalTalk
//

#import "SharedCalendarData.h"

static NSString* SharedCalendarData_keyNameEscapeString(NSString *string);

@interface SharedCalendarData (Private)

// KVO callback
- (void)observeValueForKeyPath: (NSString*)keyPath ofObject: (id)object change: (NSDictionary*)change
      context: (void*)context;

@end

#pragma mark -

@implementation SharedCalendarData

// No automatic KVO notifications
+ (BOOL)automaticallyNotifiesObserversForKey: (NSString*)key
{
    return NO;
}

- initWithCalendarName: (NSString*)calendarName calendarFileName: (NSString*)calendarFileName
{
    self = [super init];
    if(self)
    {
	m_calendarName = [calendarName retain];
	m_calendarFileName = [calendarFileName retain];
	m_calendarSharedDefaultsKey =
	    [[@"values.shareCalendar_" stringByAppendingString:
		SharedCalendarData_keyNameEscapeString(calendarName)] retain];
	// Register to observe the sharedness of this calendar in user defaults
	[[NSUserDefaultsController sharedUserDefaultsController] addObserver: self
	    forKeyPath: m_calendarSharedDefaultsKey
	    options: NSKeyValueObservingOptionNew context: NULL];
    }
    return self;
}

+ calendarDataWithCalendarName: (NSString*)calendarName calendarFileName: (NSString*)calendarFileName
{
    return [[[SharedCalendarData alloc] initWithCalendarName: calendarName calendarFileName: calendarFileName]
	       autorelease];
}

- (void)dealloc
{
    [m_calendarSharedDefaultsKey release];
    [m_calendarFileName release];
    [m_calendarName release];
    
    [super dealloc];
}

- (NSString*)description
{
	return [NSString stringWithFormat: @"<SharedCalendarData %@ @%@ %@shared>", m_calendarName, m_calendarFileName, 
					 [self calendarShared]? @"" : @"not "];
}

- (BOOL)isEqual: (id)otherObject
{
    if(otherObject == self)
		return YES;
    if(![otherObject isKindOfClass: [SharedCalendarData class]])
		return NO;
    return [m_calendarName isEqualToString: [otherObject calendarName]];
}

- (unsigned)hash
{
    return [m_calendarName hash];
}

- (void)removeFromDefaults
{
    // XXX how to remove a key through KVC?
}

- (NSString*)calendarName
{
    return m_calendarName;
}

- (NSString*)calendarFileName
{
    return m_calendarFileName;
}

- (BOOL)calendarShared
{
    id values = [[NSUserDefaultsController sharedUserDefaultsController] values];
    NSNumber *sharedValue = [values valueForKey: m_calendarSharedDefaultsKey];
    if(!sharedValue || ![sharedValue isKindOfClass: [NSNumber class]])
    {
		// Default to NO
		[values setValue: [NSNumber numberWithBool: NO] forKey: m_calendarSharedDefaultsKey];
		return NO;
    }
    else
		return [sharedValue boolValue];
}

- (void)setCalendarShared: (BOOL)newShared
{
    [[[NSUserDefaultsController sharedUserDefaultsController] values] setValue: [NSNumber numberWithBool: newShared]
	forKey: m_calendarSharedDefaultsKey];
}

@end

#pragma mark -

@implementation SharedCalendarData (Private)

- (void)observeValueForKeyPath: (NSString*)keyPath ofObject: (id)object change: (NSDictionary*)change
      context: (void*)context
{
    //if([object isEqual: [[NSUserDefaultsController sharedUserDefaultsController] values]]
    //   && [keyPath isEqualToString: m_calendarSharedDefaultsKey])
    //{
	// Signal that our sharing status has changed
	[self didChangeValueForKey: @"calendarShared"];
    //}
	//[super observeValueForKeyPath: keyPath ofObject: object change: change context: context];
}

@end

static NSString*
SharedCalendarData_keyNameEscapeString(NSString *string)
{
    // Convert all non-English-alphanumeric characters to an underscore followed by the hex Unicode index for the
    // character to make a KVC-friendly name
    NSMutableString *escapedString = [NSMutableString stringWithString: string];
    NSCharacterSet *passCharset = [NSCharacterSet characterSetWithCharactersInString: @"qwertuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM1234567890 "];
    NSRange strIndex = NSMakeRange(0, 1);
    unichar ch;
    
    while(strIndex.location < [escapedString length])
    {
	ch = [escapedString characterAtIndex: strIndex.location];
	if([passCharset characterIsMember: ch])
	    ++strIndex.location;
	else
	{
	    [escapedString replaceCharactersInRange: strIndex
			   withString: [NSString stringWithFormat: @"_%04X", ch]];
	    strIndex.location += 4;
	}
    }
    
    return escapedString;
}