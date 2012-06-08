//
//  SharedCalendarData.h
//  CalTalk
//

#import <Cocoa/Cocoa.h>


@interface SharedCalendarData : NSObject
{
    NSString *m_calendarName, *m_calendarFileName, *m_calendarSharedDefaultsKey;
}

// Initialize with the given name and filename. Designated initializer
- initWithCalendarName: (NSString*)calendarName calendarFileName: (NSString*)calendarFileName;
// Return an autoreleased object with the given name and filename
+ calendarDataWithCalendarName: (NSString*)calendarName calendarFileName: (NSString*)calendarFileName;

// Return true if the calendar name is the same for two objects
- (BOOL)isEqual: (id)otherObject;
// Return the hash value of the calendar name
- (unsigned)hash;

// Remove the user defaults key indicating whether this calendar is shared
- (void)removeFromDefaults;

// Access the name, filename, and whether the calendar is being shared
- (NSString*)calendarName;
- (NSString*)calendarFileName;
- (BOOL)calendarShared;

- (void)setCalendarShared: (BOOL)newShared;

@end
