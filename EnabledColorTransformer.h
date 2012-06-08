//
//  EnabledColorTransformer.h
//  CalTalk
//
//  A value transformer that converts a BOOL (boxed in an NSNumber) to an NSColor indicating either the
//  standard (black) text color if true or the disabled (grey) text color if false.

#import <Cocoa/Cocoa.h>


@interface EnabledColorTransformer : NSValueTransformer
{
}

@end
