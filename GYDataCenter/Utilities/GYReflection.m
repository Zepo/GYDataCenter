//
//  GYReflection.m
//  GYDBRunner
//
//  Created by Zepo She on 12/29/14.
//  Copyright (c) 2014 Tencent. All rights reserved.
//

#import "GYReflection.h"

#import <objc/runtime.h>

@implementation GYReflection

+ (NSString *)propertyTypeOfClass:(Class)classType propertyName:(NSString *)propertyName {
    static NSMutableDictionary *cache = nil;
    static dispatch_once_t pred;
    dispatch_once(&pred, ^{
        cache = [[NSMutableDictionary alloc] init];
    });
    @synchronized(cache) {
        NSMutableDictionary *propertyTypeMap = [cache objectForKey:NSStringFromClass(classType)];
        if (!propertyTypeMap) {
            propertyTypeMap = [[NSMutableDictionary alloc] init];
            [cache setObject:propertyTypeMap forKey:NSStringFromClass(classType)];
        }
        NSString *type = [propertyTypeMap objectForKey:propertyName];
        if (!type) {
            objc_property_t property = class_getProperty(classType, [propertyName UTF8String]);
            NSString *attributes = [NSString stringWithCString:property_getAttributes(property) encoding:NSUTF8StringEncoding];
            
            if ([attributes hasPrefix:@"T@"]) {
                NSArray *substrings = [attributes componentsSeparatedByString:@"\""];
                if ([substrings count] >= 2) {
                    type = [substrings objectAtIndex:1];
                } else {
                    type = @"id";
                }
            } else if ([attributes hasPrefix:@"T{"]) {
                type = @"struct";
            } else {
                if ([attributes hasPrefix:@"Ti"]) {
                    type = @"int";
                } else if ([attributes hasPrefix:@"TI"]) {
                    type = @"unsigned";
                } else if ([attributes hasPrefix:@"Ts"]) {
                    type = @"short";
                } else if ([attributes hasPrefix:@"Tl"]) {
                    type = @"long";
                } else if ([attributes hasPrefix:@"TL"]) {
                    type = @"unsigned long";
                } else if ([attributes hasPrefix:@"Tq"]) {
                    type = @"long long";
                } else if ([attributes hasPrefix:@"TQ"]) {
                    type = @"unsigned long long";
                } else if ([attributes hasPrefix:@"TB"]) {
                    type = @"bool";
                } else if ([attributes hasPrefix:@"Tf"]) {
                    type = @"float";
                } else if ([attributes hasPrefix:@"Td"]) {
                    type = @"double";
                } else if ([attributes hasPrefix:@"Tc"]) {
                    type = @"char";
                } else if ([attributes hasPrefix:@"T^i"]) {
                    type = @"int *";
                } else if ([attributes hasPrefix:@"T^I"]) {
                    type = @"unsigned *";
                } else if ([attributes hasPrefix:@"T^s"]) {
                    type = @"short *";
                } else if ([attributes hasPrefix:@"T^l"]) {
                    type = @"long *";
                } else if ([attributes hasPrefix:@"T^q"]) {
                    type = @"long long *";
                } else if ([attributes hasPrefix:@"T^Q"]) {
                    type = @"unsigned long long *";
                } else if ([attributes hasPrefix:@"T^B"]) {
                    type = @"bool *";
                } else if ([attributes hasPrefix:@"T^f"]) {
                    type = @"float *";
                } else if ([attributes hasPrefix:@"T^d"]) {
                    type = @"double *";
                } else if ([attributes hasPrefix:@"T*"]) {
                    type = @"char *";
                } else {
                    NSAssert(0, @"Unkonwn type");
                }
            }
            [propertyTypeMap setObject:type forKey:propertyName];
        }
        
        return type;
    }
}

@end
