//
//  DataIsEmptyTransformer.m
//  CalTalk
//

#import "DataIsEmptyTransformer.h"

@implementation DataIsEmptyTransformer

+ (Class)transformedValueClass
{
    return [NSNumber class];
}

+ (BOOL)allowsReverseTransformation
{
    return NO;
}

- (id)transformedValue: (id)value
{
    return [NSNumber numberWithBool: ([value respondsToSelector: @selector(isEqualToData:)]   && [value isEqualToData: [NSData data]])
				  || ([value respondsToSelector: @selector(isEqualToString:)] && [value isEqualToString: @""])
				  || ([value isEqual: [NSNull null]])
				  ||   value == nil];
}

@end
