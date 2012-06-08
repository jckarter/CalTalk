//
//  EnabledColorTransformer.m
//  CalTalk
//

#import "EnabledColorTransformer.h"


@implementation EnabledColorTransformer

+ (Class)transformedValueClass
{
    return [NSColor class];
}

+ (BOOL)allowsReverseTransformation
{
    return NO;
}

- (id)transformedValue: (id)value
{
    BOOL boolValue = [value boolValue];
    
    if(boolValue)
	return [NSColor controlTextColor];
    else
	return [NSColor disabledControlTextColor];
}

@end
