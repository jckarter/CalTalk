//
//  AutoLaunch.m
//  CalTalk
//
//  Created by Joe Groff on 6/27/05.
//  Copyright 2005 Joe Groff. All rights reserved.
//

#import "AutoLaunch.h"
#import <Carbon/Carbon.h>
#import <CoreFoundation/CoreFoundation.h>

static NSData *AutoLaunch_aliasForFile(NSString *path);
static NSArray *AutoLaunch_readAutoLaunchPlist(void);
static void AutoLaunch_writeAutoLaunchPlist(NSArray *autoLaunch);

@implementation AutoLaunch

+ (BOOL)isFileInAutoLaunch: (NSString*)path
{
	NSArray *autoLaunch = AutoLaunch_readAutoLaunchPlist();
	BOOL isFileThere = ([[autoLaunch valueForKey: @"Path"] indexOfObject: path] != NSNotFound);
	return isFileThere;
}

+ (void)addFileToAutoLaunch: (NSString*)path hide: (BOOL)hide
{
	NSMutableArray *autoLaunch = [NSMutableArray arrayWithArray: AutoLaunch_readAutoLaunchPlist()];
	NSDictionary *newAutoLaunchEntry; 
	NSData *newAutoLaunchAlias = AutoLaunch_aliasForFile(path);
	
	if(newAutoLaunchAlias)
	{
		newAutoLaunchEntry = [NSDictionary dictionaryWithObjectsAndKeys:
										   path,							@"Path",
										   [NSNumber numberWithBool: hide],	@"Hide",
										   newAutoLaunchAlias,				@"AliasData",
										   nil];
		[autoLaunch addObject: newAutoLaunchEntry];
		AutoLaunch_writeAutoLaunchPlist(autoLaunch);
	}
}

+ (void)removeFileFromAutoLaunch: (NSString*)path
{
	NSMutableArray *autoLaunch = [NSMutableArray arrayWithArray: AutoLaunch_readAutoLaunchPlist()];
	unsigned index = [[autoLaunch valueForKey: @"Path"] indexOfObject: path];
	
	if(index != NSNotFound)
	{
		[autoLaunch removeObjectAtIndex: index];
		AutoLaunch_writeAutoLaunchPlist(autoLaunch);
	}
}

@end

static NSData *
AutoLaunch_aliasForFile(NSString *path)
{
	OSStatus err;
	FSRef pathRef;
	AliasHandle pathAlias;
	NSData *pathAliasData;
	
	// Convert the path to an FSRef
	err = FSPathMakeRef([path UTF8String], &pathRef, NULL);
	if(err != noErr)
		return nil;
	// Make the alias
	err = FSNewAlias(NULL, &pathRef, &pathAlias);
	if(err != noErr)
		return nil;
	// Copy the alias data into an NSData object
	HLock((Handle)pathAlias);
	pathAliasData = [NSData dataWithBytes: *pathAlias length: (*pathAlias)->aliasSize];
	DisposeHandle((Handle)pathAlias);
	
	return pathAliasData;
}

static NSArray *
AutoLaunch_readAutoLaunchPlist(void)
{
	CFArrayRef autoLaunch = CFPreferencesCopyAppValue((CFStringRef)@"AutoLaunchedApplicationDictionary", (CFStringRef)@"loginwindow");
	if(!autoLaunch)
		return nil;
	if(CFGetTypeID(autoLaunch) != CFArrayGetTypeID())
	{
		CFRelease(autoLaunch);
		return nil;
	}
	
	return [(NSArray*)autoLaunch autorelease];
}

static void
AutoLaunch_writeAutoLaunchPlist(NSArray *autoLaunch)
{
	CFPreferencesSetAppValue((CFStringRef)@"AutoLaunchedApplicationDictionary", (CFPropertyListRef)autoLaunch, (CFStringRef)@"loginwindow");
}