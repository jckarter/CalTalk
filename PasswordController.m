#import "CalTalk.h"
#import "PasswordController.h"
#import <openssl/md5.h>
#import <string.h>

#define PASSWORDCONTROLLER_PLACEHOLDER_STRING @"x?<2}q_([\\"

@interface PasswordController (Private)

// Initialize the password entry fields
- (void)setPasswordTextFields;

// Do-nothing delegate method for alert sheets whose return we don't care about
- (void)throwAwayAlertDidEnd: (NSAlert*)alert returnCode: (int)returnCode contextInfo: (void*)contextInfo;
// Delegate method for the "Are you sure?" alert sheet raised when the user clears the password
- (void)confirmClearPasswordAlertDidEnd: (NSAlert*)alert returnCode: (int)returnCode contextInfo: (void*)contextInfo;
// Delegate method for the alert sheet raised when the user tries to close preferences without applying changes to name and password
- (void)confirmCloseAlertDidEnd: (NSAlert*)alert returnCode: (int)returnCode contextInfo: (BOOL*)shouldClose;
// Methods called on the basis of the button pressed in the above sheet
- (void)confirmCloseSave: (NSTimer*)timer;
- (void)confirmCloseCancel: (NSTimer*)timer;
- (void)confirmCloseDontSave: (NSTimer*)timer;

// Raise a throwaway alert, either as a sheet if the o_window outlet is connected or as a modal dialog if o_window is nil
- (void)raiseAlert: (NSAlert*)theAlert;
// Raise an alert and call the given selector with the return code
- (void)raiseAlert: (NSAlert*)theAlert withSelector: (SEL)selector;

// Window delegate methods
- (BOOL)windowShouldClose: (id)sender;
- (void)windowWillClose: (NSNotification*)notification;

@end

#pragma mark -

@implementation PasswordController

- init
{
    self = [super init];
    if(self)
    {
	// XXX make an IBPalette for this
	m_passwordDefaultsKeyPath = @"values.secPasswordHash";
	m_userNameDefaultsKeyPath = @"values.secUserName";
    }
    return self;
}

- (void)awakeFromNib
{
    [self setPasswordTextFields];
    
    if(o_window)
	[o_window setDelegate: self];
}

- (IBAction)setPassword: (id)sender
{
    NSString *userName = [o_userNameTextField stringValue],
	     *value1 = [o_passwordTextField1 stringValue],
	     *value2 = [o_passwordTextField2 stringValue];
    BOOL didHavePassword = [self hasPassword],
	 willChangeHavePassword = (didHavePassword && [value1 isEqualToString: @""]) || (!didHavePassword && ![value1 isEqualToString: @""]),
	 willChangeUserName = ![userName isEqualToString: [self userName]];
    
    NSAssert(m_passwordDefaultsKeyPath != nil, @"passwordDefaultsKey of PasswordController must not be nil");
    
    // Does the username have illegal characters? Then reject it
    if(   [userName rangeOfString: @":" ].location != NSNotFound
       || [userName rangeOfString: @"\""].location != NSNotFound)
    {
	[self raiseAlert: [NSAlert alertWithMessageText: NSLocalizedString(@"Invalid characters in user name", @"")
				   defaultButton: nil
				   alternateButton: nil
				   otherButton: nil
				   informativeTextWithFormat: NSLocalizedString(@"Your user name cannot include colons (:) or quotation "
										 "marks (\").", @"")]];
    }
    // Do the two entered passwords not match? Then reject them
    else if(![value1 isEqualToString: value2])
    {
	[self raiseAlert: [NSAlert alertWithMessageText: NSLocalizedString(@"Entered passwords do not match", @"")
				   defaultButton: nil
				   alternateButton: nil
				   otherButton: nil
				   informativeTextWithFormat: NSLocalizedString(@"Make sure you entered the same password into both boxes, then "
										 "click the \"Set Name and Password\" button again.", @"")]];
    }
    // Did the user enter a new password? Then set it
    else if(![value1 isEqualToString: PASSWORDCONTROLLER_PLACEHOLDER_STRING] && ![value1 isEqualToString: @""])
    {
	NSData *passwordValue = CalTalk_md5HashDataForString(
	    [NSString stringWithFormat: @"%@:%@:%@", userName, [self realm], value1]
	);
	
	if(willChangeUserName)
	{
	    [self willChangeValueForKey: @"userName"];
	    [[NSUserDefaultsController sharedUserDefaultsController] setValue: userName forKeyPath: m_userNameDefaultsKeyPath];
	    [self didChangeValueForKey: @"userName"];
	}

	if(willChangeHavePassword)
	    [self willChangeValueForKey: @"hasPassword"];
	[[NSUserDefaultsController sharedUserDefaultsController] setValue: passwordValue forKeyPath: m_passwordDefaultsKeyPath];
	if(willChangeHavePassword)
	    [self didChangeValueForKey: @"hasPassword"];
	    
	[self setPasswordTextFields];
    }
    // Did the user change their name while leaving the password blank? Then change the username
    else if([value1 isEqualToString: @""] && !didHavePassword && willChangeUserName)
    {
	[self willChangeValueForKey: @"userName"];
	[[NSUserDefaultsController sharedUserDefaultsController] setValue: userName forKeyPath: m_userNameDefaultsKeyPath];
	[self didChangeValueForKey: @"userName"];
    }
    // Is the user trying to clear their password? Then confirm before clearing it
    else if([value1 isEqualToString: @""] && didHavePassword)
    {
	// Confirm that the user really wants to clear the password
	[self raiseAlert: [NSAlert alertWithMessageText: NSLocalizedString(@"Clearing password", @"")
				   defaultButton:	 NSLocalizedString(@"Clear Password", @"")
				   alternateButton:	 NSLocalizedString(@"Cancel", @"")
				   otherButton: nil
				   informativeTextWithFormat: NSLocalizedString(@"You are about to clear the password on your shared "
										 "calendars. Anyone on the network will be able to see "
										 "them.", @"")]
	      withSelector: @selector(confirmClearPasswordAlertDidEnd:returnCode:contextInfo:)];
    }
    // Otherwise, a new password hasn't been entered at all
    else
    {
	NSString *informativeText;
	
	// Print an explanation telling why the user must reenter their password if they
	// try only to change their username
	if(willChangeUserName && didHavePassword)
	    informativeText = NSLocalizedString(@"You must enter a new password into both boxes before "
						 "clicking the \"Set Name and Password\" button, even if you only "
						 "want to change your user name. For security, CalTalk "
						 "does not save your password in a format independent of "
						 "your username.", @"");
	else
	    informativeText = NSLocalizedString(@"You must enter a new password into both boxes before "
						 "clicking the \"Set Name and Password\" button.", @"");
	
	[self raiseAlert: [NSAlert alertWithMessageText: NSLocalizedString(@"A new password wasn't entered", @"")
				   defaultButton: nil
				   alternateButton: nil
				   otherButton: nil
				   informativeTextWithFormat: informativeText]];
    }
}

- (NSString*)passwordDefaultsKey
{
    // Cut off the "values." part of the key path
    return [m_passwordDefaultsKeyPath substringFromIndex: 7];
}

- (void)setPasswordDefaultsKey: (NSString*)newKey
{
    NSString *oldKeyPath = m_passwordDefaultsKeyPath;

    m_passwordDefaultsKeyPath = [[NSString alloc] initWithFormat: @"values.%@", newKey];
    [oldKeyPath release];
}

- (NSString*)userNameDefaultsKey
{
    // Cut off the "values." part of the key path
    return [m_userNameDefaultsKeyPath substringFromIndex: 7];
}

- (void)setUserNameDefaultsKey: (NSString*)newKey
{
    NSString *oldKeyPath = m_userNameDefaultsKeyPath;
    m_userNameDefaultsKeyPath = [[NSString alloc] initWithFormat: @"values.%@", newKey];
    [oldKeyPath release];
}

- (NSString*)userName
{
    return [[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath: m_userNameDefaultsKeyPath];
}

- (NSString*)realm
{
    // We can't change this because doing so would require us to rehash the password for digest auth
    return @"CalTalk";
}

- (NSData*)passwordHash
{
    return [[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath: m_passwordDefaultsKeyPath];
}

- (BOOL)isPasswordCorrect: (NSString*)password
{
    NSData *passwordHash = [[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath: m_passwordDefaultsKeyPath];
    
    if([passwordHash isEqualToData: [NSData data]])
	return [password isEqualToString: @""];
    return [passwordHash isEqualToData: CalTalk_md5HashDataForString(
	       [NSString stringWithFormat: @"%@:%@:%@", [self userName], [self realm], password]
	   )];
}

- (BOOL)hasPassword
{
    NSData *passwordHash = [[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath: m_passwordDefaultsKeyPath];
    return [passwordHash respondsToSelector: @selector(isEqualToData:)] && ![passwordHash isEqualToData: [NSData data]];
}

@end

#pragma mark -

@implementation PasswordController (Private)

- (void)setPasswordTextFields
{
    NSString *value = [self hasPassword]? PASSWORDCONTROLLER_PLACEHOLDER_STRING : @"";
    
    [o_userNameTextField  setStringValue: [[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath: m_userNameDefaultsKeyPath]];
    [o_passwordTextField1 setStringValue: value];
    [o_passwordTextField2 setStringValue: value];
}

- (void)throwAwayAlertDidEnd: (NSAlert*)alert returnCode: (int)returnCode contextInfo: (void*)contextInfo
{
    [o_window makeKeyAndOrderFront: self];
}

- (void)confirmClearPasswordAlertDidEnd: (NSAlert*)alert returnCode: (int)returnCode contextInfo: (void*)contextInfo
{
    if(returnCode == NSAlertFirstButtonReturn || returnCode == NSAlertDefaultReturn)
    {
	NSString *userName = [o_userNameTextField stringValue];
	if(![userName isEqualToString: [self userName]])
	{
	    [self willChangeValueForKey: @"userName"];
	    [[NSUserDefaultsController sharedUserDefaultsController] setValue: userName forKeyPath: m_userNameDefaultsKeyPath];
	    [self didChangeValueForKey: @"userName"];
	}

	[self willChangeValueForKey: @"hasPassword"];
	[[NSUserDefaultsController sharedUserDefaultsController] setValue: [NSData data] forKeyPath: m_passwordDefaultsKeyPath];
	[self didChangeValueForKey: @"hasPassword"];
    }
    [o_window makeKeyAndOrderFront: self];
}

- (void)confirmCloseAlertDidEnd: (NSAlert*)alert returnCode: (int)returnCode contextInfo: (BOOL*)shouldCloseRet
{
    SEL timerSel;
    
    if(returnCode == NSAlertFirstButtonReturn || returnCode == NSAlertDefaultReturn) // Save
	timerSel = @selector(confirmCloseSave:);
    else if(returnCode == NSAlertThirdButtonReturn || returnCode == NSAlertOtherReturn) // Cancel
	timerSel = @selector(confirmCloseCancel:);
    else if(returnCode == NSAlertSecondButtonReturn || returnCode == NSAlertAlternateReturn) // Don't Save
	timerSel = @selector(confirmCloseDontSave:);
    [NSTimer scheduledTimerWithTimeInterval: 0.001 target: self selector: timerSel userInfo: nil repeats: NO];
    [o_window makeKeyAndOrderFront: self];
}

- (void)confirmCloseSave: (NSTimer*)timer
{
    [self setPassword: self];
    // Close if the setting is successful
    if(  ([[o_passwordTextField1 stringValue] isEqualToString: PASSWORDCONTROLLER_PLACEHOLDER_STRING]
       || [[o_passwordTextField1 stringValue] isEqualToString: @""])
       && [[o_passwordTextField1 stringValue] isEqualToString: [o_passwordTextField2 stringValue]]
       && [[o_userNameTextField  stringValue]
	      isEqualToString: [[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath: m_userNameDefaultsKeyPath]])
	[o_window performClose: self];	
}

- (void)confirmCloseDontSave: (NSTimer*)timer
{
    [self setPasswordTextFields];
    [o_window performClose: self];
}

- (void)confirmCloseCancel: (NSTimer*)timer
{
    // nothing
}

- (void)raiseAlert: (NSAlert*)theAlert
{
    [self raiseAlert: theAlert withSelector: @selector(throwAwayAlertDidEnd:returnCode:contextInfo:)];
}

- (void)raiseAlert: (NSAlert*)theAlert withSelector: (SEL)selector
{
    int returnCode;
    void *nullPtr = NULL;
    
    if(!o_window)
    {
	// Raise alert modally
	returnCode = [theAlert runModal];
	NSInvocation *callbackInvocation = [NSInvocation invocationWithMethodSignature: [self methodSignatureForSelector: selector]];
	[callbackInvocation setTarget: self];
	[callbackInvocation setSelector: selector];
	[callbackInvocation setArgument: &theAlert   atIndex: 2];
	[callbackInvocation setArgument: &returnCode atIndex: 3];
	[callbackInvocation setArgument: &nullPtr    atIndex: 4];
	[callbackInvocation invoke];
    }
    else
    {
	// Run as a sheet on the containing window
	[theAlert beginSheetModalForWindow: o_window modalDelegate: self didEndSelector: selector contextInfo: NULL];
    }
}

- (BOOL)windowShouldClose: (id)sender
{
    NSString *userName = [o_userNameTextField  stringValue],
	     *value1   = [o_passwordTextField1 stringValue],
	     *value2   = [o_passwordTextField2 stringValue],
	     *savedUserName = [[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath: m_userNameDefaultsKeyPath];
    if(    [userName isEqualToString: savedUserName]
       && ([value1 isEqualToString: PASSWORDCONTROLLER_PLACEHOLDER_STRING] || [value1 isEqualToString: @""])
       && ([value2 isEqualToString: value1]))
    {
	return YES;
    }
    else
    {
	[[NSAlert alertWithMessageText: NSLocalizedString(@"Changes to password have not been saved", @"")
		  defaultButton:        NSLocalizedString(@"Save", @"")
		  alternateButton:	NSLocalizedString(@"Don't Save", @"")
		  otherButton:		NSLocalizedString(@"Cancel", @"")
		  informativeTextWithFormat: NSLocalizedString(@"Do you want to save your changed username and password before closing "
								"this panel?", @"")]
	    beginSheetModalForWindow: o_window
	    modalDelegate: self
	    didEndSelector: @selector(confirmCloseAlertDidEnd:returnCode:contextInfo:)
	    contextInfo: NULL];
	return NO;
    }
}

- (void)windowWillClose: (NSNotification*)notification
{
    // Reset the password fields
    [self setPasswordTextFields];
}

@end

NSData *
CalTalk_md5HashDataForString(NSString *str)
{
    unsigned char md5Hash[MD5_DIGEST_LENGTH];
    const char *cStr = [str UTF8String];

    MD5((const unsigned char *)cStr, strlen(cStr), md5Hash);
    return [NSData dataWithBytes: md5Hash length: MD5_DIGEST_LENGTH];
}