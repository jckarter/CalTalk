//
//  DataIsEmptyTransformer.h
//  CalTalk
//
//  A value transformer that converts an NSData to an NSNumber containing a BOOL indicating whether the data
//  is empty (0 bytes long)

#import <Cocoa/Cocoa.h>


@interface DataIsEmptyTransformer : NSValueTransformer
{
}
@end
