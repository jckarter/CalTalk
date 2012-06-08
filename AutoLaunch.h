//
//  AutoLaunch.h
//  CalTalk
//
//	A class to manage the addition and removal of startup items from a user's settings.
//
//  Created by Joe Groff on 6/27/05.
//  Copyright 2005 Joe Groff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AutoLaunch : NSObject
{
}

// See whether the current path is set to autolaunch
+ (BOOL)isFileInAutoLaunch: (NSString*)path;

// Add or remove files from autolaunch
+ (void)addFileToAutoLaunch: (NSString*)path hide: (BOOL)hide;
+ (void)removeFileFromAutoLaunch: (NSString*)path;

@end
