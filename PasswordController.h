/* PasswordController */

#import <Cocoa/Cocoa.h>

@interface PasswordController : NSObject
{
    IBOutlet NSTextField *o_userNameTextField;
    IBOutlet NSTextField *o_passwordTextField1;
    IBOutlet NSTextField *o_passwordTextField2;
    IBOutlet NSWindow *o_window;
    
@private
    NSString *m_userNameDefaultsKeyPath;
    NSString *m_passwordDefaultsKeyPath;
}

// Action called by the "Set Password" button to commit the entered password
- (IBAction)setPassword: (id)sender;

// Get and set the user defaults keys under which the  hashed password should be kept. This must be set
// from the controller's awakeFromNib for the object to be able to save its password.
- (NSString*)passwordDefaultsKey;
- (void)setPasswordDefaultsKey: (NSString*)newKey;
- (NSString*)userNameDefaultsKey;
- (void)setUserNameDefaultsKey: (NSString*)newKey;

// Return the user name
- (NSString*)userName;
// Return the authentication realm
- (NSString*)realm;
// Return the password hash
- (NSData*)passwordHash;
// Check the given password against the hashed password value
- (BOOL)isPasswordCorrect: (NSString*)password;

// Return whether a password is set
- (BOOL)hasPassword;

@end
