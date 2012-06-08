/* CalTalkController */

#import <Cocoa/Cocoa.h>
#import "PasswordController.h"

@class CalTalkServer;

@interface CalTalkController : NSObjectController
{
    IBOutlet NSArrayController *o_networkUsersController, *o_networkCalendarsController, *o_myCalendarsController;
    IBOutlet NSWindow *o_calendarsWindow;
    IBOutlet NSTabView *o_calendarsTabView;
    IBOutlet NSPanel *o_preferencesPanel;
    IBOutlet NSTabView *o_preferencesTabView;
    IBOutlet NSTableView *o_networkCalendarsTableView;
    IBOutlet NSTableColumn *o_networkUsersTableColumn;
    IBOutlet NSPanel *o_quitConfirmPanel;
    IBOutlet PasswordController *o_passwordController;
    IBOutlet NSPanel *o_passwordSheet;
    IBOutlet NSTextField *o_passwordSheetUsernameTextField;
    IBOutlet NSTextField *o_passwordSheetPasswordTextField;
    IBOutlet NSButton *o_passwordSheetStoreInKeychainButton;
    
    CalTalkServer *m_server;
}

- (IBAction)refreshUsersList:(id)sender;
- (IBAction)showMyCalendarsTab:(id)sender;
- (IBAction)showNetworkTab:(id)sender;
- (IBAction)showSecurityPreferencesTab:(id)sender;
- (IBAction)subscribeToCalendar:(id)sender;
- (IBAction)goToICal:(id)sender;
- (IBAction)confirmQuit:(id)sender;
- (IBAction)dismissPasswordPanel:(id)sender;

// Get the server object
- (CalTalkServer*)server;
// Get the main window object
- (NSWindow*)calendarsWindow;
// Get the password panel object and its entry fields
- (NSPanel*)passwordPanel;
- (NSTextField*)passwordPanelUsernameTextField;
- (NSTextField*)passwordPanelPasswordTextField;
- (NSButton*)passwordPanelStoreInKeychainButton;
// Get the password controller object
- (PasswordController*)passwordController;

// NSApplication delegate methods
- (void)applicationDidBecomeActive: (NSNotification*)notification;
- (BOOL)applicationShouldHandleReopen: (NSApplication*)app hasVisibleWindows: (BOOL)hasWindows;

// Delegate method for alert sheets whose return we don't care about
- (void)throwAwayAlertDidEnd: (NSAlert*)alert returnCode: (int)returnCode contextInfo: (void*)contextInfo;

@end
