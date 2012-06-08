//
//  NSData_HexRepresentation.h
//  CalTalk
//
//  Add a category to NSData to return a string representing the data as a flat hex string, without any of the
//  formatting that -description adds
//

#import <Cocoa/Cocoa.h>


@interface NSData (HexRepresentation)

- (NSString*)hexRepresentation;

+ (NSData*)dataFromHexRepresentation: (NSString*)hexRep;

@end


#if 0
@interface NSObject (LogUndefinedKeys)

- (id)valueForUndefinedKey: (NSString*)key;

@end
#endif