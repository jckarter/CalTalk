#import "AutoLaunch.h"
#import "CalTalk.h"
#import "CalTalkController.h"
#import "CalTalkData.h"
#import "CalTalkServer.h"
#import "NetworkUserData.h"
#import "SharedCalendarData.h"
#import "DataIsEmptyTransformer.h"
#import "EnabledColorTransformer.h"

CalTalkController *g_calTalkController = nil;

@interface CalTalkController (Private)

- (void)observeValueForKeyPath: (NSString*)keyPath ofObject: (id)object change: (NSDictionary*)change context: (void*)context;

@end

@implementation CalTalkController

+ (void)initialize
{
    NSUserDefaultsController *sharedController;
    DataIsEmptyTransformer *transformer;

    // Set initial values for user defaults
    sharedController = [NSUserDefaultsController sharedUserDefaultsController];
    [sharedController setInitialValues:
	[NSDictionary dictionaryWithObjectsAndKeys:
	    NSFullUserName(),					@"shareName",
	    [NSNumber numberWithUnsignedShort: 24080],		@"sharePort",
	    [NSNumber numberWithBool: NO],			@"showInStatusArea",
	    [NSNumber numberWithBool: YES],			@"confirmQuit",
	    [NSNumber numberWithBool: YES],			@"showInDock",
	    [NSNumber numberWithBool: NO],			@"startOnLogin",
	    [NSNumber numberWithBool: NO],			@"shareCalendars",
	    [NSString stringWithFormat: @"(%@)", NSUserName()],	@"addToNameText",
	    [NSNumber numberWithBool: YES],			@"addToName",
	    NSUserName(),					@"secUserName",
	    [NSData data],					@"secPasswordHash",
	    [NSNumber numberWithBool: (NSAppKitVersionNumber >= 800.0? YES : NO)],
								@"secDigestAuth",
	    [NSNumber numberWithBool: YES],			@"secStoreInKeychainByDefault",
	    nil]];

    // Register custom value transformers
    transformer = [[[DataIsEmptyTransformer alloc] init] autorelease];
    [NSValueTransformer setValueTransformer: transformer forName: @"DataIsEmpty"];
    transformer = [[[EnabledColorTransformer alloc] init] autorelease];
    [NSValueTransformer setValueTransformer: transformer forName: @"EnabledColor"];
}

- (void)awakeFromNib
{
    id userDefaultsController;
    
    if(g_calTalkController)
	    NSLog(@"Warning! More than one CalTalkController instance!\n");
    g_calTalkController = self;
    
    // Set the double-click action for the network calendars view
    [o_networkCalendarsTableView setTarget: self];
    [o_networkCalendarsTableView setDoubleAction: @selector(subscribeToCalendar:)];
    
    // Create the server object
    m_server = [[CalTalkServer alloc] initWithController: self];
    // If we're set to share, start the server
    userDefaultsController = [NSUserDefaultsController sharedUserDefaultsController];
    // Watch the shareCalendars pref so we know when to start and stop the server
    [userDefaultsController addObserver: self forKeyPath: @"values.shareCalendars" options: NSKeyValueObservingOptionNew context: NULL];
    //NSLog(@"shareCalendars: %@\n", [userDefaultsController valueForKeyPath: @"values.shareCalendars"]); // XXX
    if([[userDefaultsController valueForKeyPath: @"values.shareCalendars"] boolValue])
	[m_server start];

    // If we're in the autolaunch list, set the startOnLogin pref accordingly
    // XXX this causes a 72-byte leak…
    [userDefaultsController
	setValue: [NSNumber numberWithBool: [AutoLaunch isFileInAutoLaunch: [[NSBundle mainBundle] bundlePath]]]
	forKeyPath: @"values.startOnLogin"];
    // Watch the startOnLogin pref so we can add/remove ourselves from the list
    [userDefaultsController addObserver: self forKeyPath: @"values.startOnLogin" options: NSKeyValueObservingOptionNew context: NULL];
}

- (IBAction)refreshUsersList:(id)sender
{
    // XXX This would be better named refreshUserCalendarsList:, but I'm too lazy right now to change the
    // nib connections
    
    // Get the selected user
    unsigned selectedUserIndex = [o_networkUsersController selectionIndex];
    
    if(selectedUserIndex != NSNotFound)
    {
	NetworkUserData *selectedUserData = [[_content networkUsers] objectAtIndex: selectedUserIndex];
	[selectedUserData refreshSharedCalendars];
    }
}

- (IBAction)showMyCalendarsTab:(id)sender
{
    // Bring the calendars window to front, then activate the first tab
    [o_calendarsTabView selectTabViewItemWithIdentifier: @"My Calendars"];
    [o_calendarsWindow makeKeyAndOrderFront: self];
}

- (IBAction)showNetworkTab:(id)sender
{
    // Bring the calendars window to front, then activate the second tab
    [o_calendarsTabView selectTabViewItemWithIdentifier: @"Network"];
    [o_calendarsWindow makeKeyAndOrderFront: self];
}

- (IBAction)showSecurityPreferencesTab:(id)sender
{
    // Open the preferences window and switch to the Security tab
    [o_preferencesTabView selectTabViewItemWithIdentifier: @"Security"];
    [o_preferencesPanel makeKeyAndOrderFront: self];
}

- (IBAction)subscribeToCalendar:(id)sender
{
    unsigned selectedUserIndex = [o_networkUsersController selectionIndex],
	     selectedCalendarIndex = [o_networkCalendarsController selectionIndex];
    
    if(selectedUserIndex != NSNotFound && selectedCalendarIndex != NSNotFound)
    {
	NetworkUserData *selectedUserData = [[_content networkUsers] objectAtIndex: selectedUserIndex];
	NSString *selectedCalendarName = [[selectedUserData sharedCalendars] objectAtIndex: selectedCalendarIndex];
	NSURL *calendarURL = [selectedUserData URLForCalendar: selectedCalendarName];
	NSMutableString *calendarURLString = [NSMutableString stringWithString: [calendarURL absoluteString]];
	
	// iCal 1.x ignores GetURL requests for http:// URLs, so change the scheme to webcal://
	[calendarURLString replaceOccurrencesOfString: @"http:" withString: @"webcal:" options: NSCaseInsensitiveSearch
					   range: NSMakeRange(0, [calendarURLString length])];
	
	// Open the calendar in iCal
	NSString *iCalSubscribeScriptString = [NSString stringWithFormat:
							@"tell app \"iCal\"\n"
							 "	launch\n"
							 "	activate\n"
							 "	ignoring application responses\n"
							 "		GetURL \"%@\"\n"
							 "	end ignoring\n"
							 "end tell\n",
							calendarURLString];
	NSAppleScript *iCalSubscribeScript = [[NSAppleScript alloc] initWithSource: iCalSubscribeScriptString];
	NSDictionary *scriptErrorInfo;
	
	NSString *progressString = [NSString stringWithFormat: NSLocalizedString(@"Subscribing to %@'s %@", @""),
							       [selectedUserData userName],
							       selectedCalendarName];
	[[self content]	addJobToProgress: progressString];
	if(![iCalSubscribeScript executeAndReturnError: &scriptErrorInfo])
	{
	    [[NSAlert alertWithMessageText: NSLocalizedString(@"Subscribe Error", @"")
		      defaultButton: nil
		      alternateButton: nil
		      otherButton: nil
		      informativeTextWithFormat:
			  NSLocalizedString(@"There was an error subscribing to the calendar \"%@\". iCal returned the following "
			    "error message:\n\n"
			    "%@", @""), selectedCalendarName, [scriptErrorInfo objectForKey: NSAppleScriptErrorMessage]]
		beginSheetModalForWindow: o_calendarsWindow modalDelegate: self didEndSelector: @selector(throwAwayAlertDidEnd:returnCode:contextInfo:)
		contextInfo: NULL];
	}
	[[self content]	removeJobFromProgress: progressString];

	[iCalSubscribeScript release];
    }
}

- (IBAction)goToICal: (id)sender
{
    NSAppleScript *iCalActivateScript = [[NSAppleScript alloc] initWithSource:
	@"tell app \"iCal\"\n"
	 "	launch\n"
	 "	activate\n"
	 "end tell\n"];
    NSDictionary *scriptErrorInfo;
    
    [[self content] addJobToProgress: NSLocalizedString(@"Switching to iCal", @"")];
    if(![iCalActivateScript executeAndReturnError: &scriptErrorInfo])
    {
	[[NSAlert alertWithMessageText: NSLocalizedString(@"Error Switching to iCal", @"")
		  defaultButton: nil
		  alternateButton: nil
		  otherButton: nil
		  informativeTextWithFormat:
		      NSLocalizedString(@"iCal returned the following error message while trying to switch to it:\n\n"
					 "%@", @""), [scriptErrorInfo objectForKey: NSAppleScriptErrorMessage]]
	    beginSheetModalForWindow: o_calendarsWindow modalDelegate: self didEndSelector: @selector(throwAwayAlertDidEnd:returnCode:contextInfo:)
	    contextInfo: NULL];
    }
    [[self content] removeJobFromProgress: NSLocalizedString(@"Switching to iCal", @"")];
}

- (IBAction)confirmQuit:(id)sender
{
    NSUserDefaultsController *sharedController = [NSUserDefaultsController sharedUserDefaultsController];

    if([[[sharedController values] valueForKey: @"confirmQuit"] boolValue]
       && [[[sharedController values] valueForKey: @"shareCalendars"] boolValue])
	[o_quitConfirmPanel makeKeyAndOrderFront: self];
    else
	[NSApp terminate: self];
}

- (IBAction)dismissPasswordPanel:(id)sender
{
    [NSApp endSheet: o_passwordSheet returnCode: [sender tag]];
}

- (CalTalkServer*)server
{
    return m_server;
}

- (NSWindow*)calendarsWindow
{
    return o_calendarsWindow;
}

- (NSPanel*)passwordPanel
{
    return o_passwordSheet;
}

- (NSTextField*)passwordPanelUsernameTextField
{
    return o_passwordSheetUsernameTextField;
}

- (NSTextField*)passwordPanelPasswordTextField
{
    return o_passwordSheetPasswordTextField;
}

- (NSButton*)passwordPanelStoreInKeychainButton
{
    return o_passwordSheetStoreInKeychainButton;
}

- (PasswordController*)passwordController
{
    return o_passwordController;
}

- (void)applicationDidBecomeActive: (NSNotification*)notification
{
	// Reveal the calendars window
	[o_calendarsWindow makeKeyAndOrderFront: self];
}

- (BOOL)applicationShouldHandleReopen: (NSApplication*)app hasVisibleWindows: (BOOL)hasWindows
{
	// Reveal the calendars window
	[o_calendarsWindow makeKeyAndOrderFront: self];
	return YES;
}

- (void)throwAwayAlertDidEnd: (NSAlert*)alert returnCode: (int)returnCode contextInfo: (void*)contextInfo
{
    // do nothing
}

@end

#pragma mark -

@implementation CalTalkController (Private)

- (void)observeValueForKeyPath: (NSString*)keyPath ofObject: (id)object change: (NSDictionary*)change context: (void*)context
{
    id userDefaultsController = [NSUserDefaultsController sharedUserDefaultsController];
    if([object isEqual: userDefaultsController])
    {
	if([keyPath isEqualToString: @"values.shareCalendars"])
	{
	    if([[userDefaultsController valueForKeyPath: @"values.shareCalendars"] boolValue])
		[m_server start];
	    else
		[m_server stop];
	}
	else if([keyPath isEqualToString: @"values.startOnLogin"])
	{
	    if([[userDefaultsController valueForKeyPath: @"values.startOnLogin"] boolValue])
		[AutoLaunch addFileToAutoLaunch: [[NSBundle mainBundle] bundlePath] hide: YES];
	    else
		[AutoLaunch removeFileFromAutoLaunch: [[NSBundle mainBundle] bundlePath]];
	}
    }
    
    [super observeValueForKeyPath: keyPath ofObject: object change: change context: context];
}

@end