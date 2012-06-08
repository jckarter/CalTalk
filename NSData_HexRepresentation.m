//
//  NSData_HexRepresentation.m
//  CalTalk
//

#import "NSData_HexRepresentation.h"

static const char *NSDATA_HEX_DIGITS = "0123456789abcdef";

@implementation NSData (HexRepresentation)

- (NSString*)hexRepresentation
{
    unsigned length = [self length], i;
    const unsigned char *bytes = [self bytes];
    NSMutableString *returnString = [NSMutableString stringWithCapacity: length*2];

    for(i = 0; i < length; ++i)
    {
	[returnString appendFormat: @"%02x", bytes[i]];
    }
    return returnString;
}

+ (NSData*)dataFromHexRepresentation: (NSString*)hexRep
{
    NSString *hexRepLowercase = [hexRep lowercaseString];
    unsigned hexRepLength = [hexRep length], i;
    NSMutableData *ret = [NSMutableData dataWithCapacity: hexRepLength/2];
    
    for(i = 0; i+1 < hexRepLength; i+=2)
    {
	const char *msCharIndex = strchr(NSDATA_HEX_DIGITS, [hexRepLowercase characterAtIndex: i]),
		   *lsCharIndex = strchr(NSDATA_HEX_DIGITS, [hexRepLowercase characterAtIndex: i+1]);
	if(!msCharIndex || !lsCharIndex)
	    return nil;
	const char hexByte = ((msCharIndex - NSDATA_HEX_DIGITS) << 4) | (lsCharIndex - NSDATA_HEX_DIGITS);
	[ret appendBytes: &hexByte length: 1];
    }
    return ret;
}

@end

#if 0
@implementation NSObject (LogUndefinedKeys)

- (id)valueForUndefinedKey: (NSString*)key
{
    NSLog(@"%p (%@): Undefined key %@\n", self, [self description], key);
    abort();
}

@end
#endif