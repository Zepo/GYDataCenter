//
//  GYDCUtilities.m
//  GYDataCenter
//
//  Created by Zepo She on 1/26/15.
//  Copyright (c) 2015 Tencent. All rights reserved.
//

#import "GYDCUtilities.h"

#import "GYModelObject.h"
#import "GYReflection.h"
#import <objc/runtime.h>

@implementation GYDCUtilities

+ (GYPropertyType)propertyTypeOfClass:(Class)classType propertyName:(NSString *)propertyName {
    NSString *type = [GYReflection propertyTypeOfClass:classType propertyName:propertyName];
    if ([@"int" isEqualToString:type] ||
        [@"unsigned" isEqualToString:type] ||
        [@"short" isEqualToString:type] ||
        [@"long" isEqualToString:type] ||
        [@"unsigned long" isEqualToString:type] ||
        [@"long long" isEqualToString:type] ||
        [@"unsigned long long" isEqualToString:type] ||
        [@"char" isEqualToString:type]) {
        return GYPropertyTypeInteger;
    } else if ([@"float" isEqualToString:type] ||
               [@"double" isEqualToString:type]) {
        return GYPropertyTypeFloat;
    } else if ([@"NSString" isEqualToString:type] ||
               [@"NSMutableString" isEqualToString:type]) {
        return GYPropertyTypeString;
    } else if ([@"bool" isEqualToString:type]) {
        return GYPropertyTypeBoolean;
    } else if ([@"NSDate" isEqualToString:type]) {
        return GYPropertyTypeDate;
    } else if ([@"NSData" isEqualToString:type] ||
               [@"NSMutableData" isEqualToString:type]) {
        return GYPropertyTypeData;
    } else {
        Class propertyClass = NSClassFromString(type);
        
        if ([propertyClass isSubclassOfClass:[GYModelObject class]]) {
            return GYPropertyTypeRelationship;
        }
        
        if ([propertyClass conformsToProtocol:@protocol(GYTransformableProtocol)]) {
            return GYPropertyTypeTransformable;
        }
        return GYPropertyTypeUndefined;
    }
}

#ifdef COLUMN_MAPPING

+ (NSArray *)persistentPropertiesForClass:(Class<GYModelObjectProtocol>)modelClass {
    return [[modelClass columnMapping] allKeys];
}

+ (NSArray *)allColumnsForClass:(Class<GYModelObjectProtocol>)modelClass {
    return [[modelClass columnMapping] allValues];
}

+ (NSString *)columnForClass:(Class<GYModelObjectProtocol>)modelClass
                    property:(NSString *)property {
    return [[modelClass columnMapping] objectForKey:property];
}

+ (NSString *)propertyForClass:(Class<GYModelObjectProtocol>)modelClass
                        column:(NSString *)column {
    static const void * const kColumnPropertyMappingKey = &kColumnPropertyMappingKey;
    NSMutableDictionary *mapping = objc_getAssociatedObject(modelClass, kColumnPropertyMappingKey);
    if (!mapping) {
        mapping = [[NSMutableDictionary alloc] init];
        NSDictionary *columnMapping = [modelClass columnMapping];
        for (NSString *property in columnMapping) {
            [mapping setObject:property forKey:[columnMapping objectForKey:property]];
        }
        objc_setAssociatedObject(modelClass, kColumnPropertyMappingKey, mapping, OBJC_ASSOCIATION_COPY);
    }
    return [mapping objectForKey:column];
}

#else

+ (NSArray *)persistentPropertiesForClass:(Class<GYModelObjectProtocol>)modelClass {
    return [modelClass persistentProperties];
}

+ (NSArray *)allColumnsForClass:(Class<GYModelObjectProtocol>)modelClass {
    if ([modelClass fts] && [modelClass primaryKey]) {
        NSMutableArray *columns = [[modelClass persistentProperties] mutableCopy];
        [columns removeObject:[modelClass primaryKey]];
        [columns addObject:@"docid"];
        return columns;
    }
    return [modelClass persistentProperties];
}

+ (NSString *)columnForClass:(Class<GYModelObjectProtocol>)modelClass
                    property:(NSString *)property {
    if ([modelClass fts] && [property isEqualToString:[modelClass primaryKey]]) {
        return @"docid";
    }
    return property;
}

+ (NSString *)propertyForClass:(Class<GYModelObjectProtocol>)modelClass
                        column:(NSString *)column {
    if ([modelClass fts] && [@"docid" isEqualToString:column]) {
        return [modelClass primaryKey];
    }
    return column;
}

#endif

+ (NSString *)recoverDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];
    return [documentsDirectory stringByAppendingPathComponent:@"GYDataCenterRecover"];
}

@end
