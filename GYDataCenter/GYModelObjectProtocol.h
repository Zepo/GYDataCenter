//
//  GYModelObjectProtocol.h
//  GYDataCenter
//
//  Created by 佘泽坡 on 6/30/16.
//  Copyright © 2016 佘泽坡. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, GYCacheLevel) {
    GYCacheLevelNoCache,
    GYCacheLevelDefault,
    GYCacheLevelResident
};

@protocol GYModelObjectProtocol <NSObject>

@property (nonatomic, getter=isCacheHit, readonly) BOOL cacheHit;
@property (nonatomic, getter=isFault, readonly) BOOL fault;
@property (nonatomic, getter=isSaving, readonly) BOOL saving;
@property (nonatomic, getter=isDeleted, readonly) BOOL deleted;

+ (NSString *)dbName;
+ (NSString *)tableName;
+ (NSString *)primaryKey;
+ (NSArray *)persistentProperties;

+ (NSDictionary *)propertyTypes;
+ (NSDictionary *)propertyClasses;
+ (NSSet *)relationshipProperties;

+ (GYCacheLevel)cacheLevel;

+ (NSString *)fts;

@optional
+ (NSArray *)indices;
+ (NSDictionary *)defaultValues;

+ (NSString *)tokenize;

@end

@protocol GYTransformableProtocol <NSObject>

+ (NSData *)transformedValue:(id)value;
+ (id)reverseTransformedValue:(NSData *)value;

@end

typedef NS_ENUM(NSUInteger, GYPropertyType) {
    GYPropertyTypeUndefined,
    GYPropertyTypeInteger,
    GYPropertyTypeFloat,
    GYPropertyTypeString,
    GYPropertyTypeBoolean,
    GYPropertyTypeDate,
    GYPropertyTypeData,
    GYPropertyTypeTransformable,
    GYPropertyTypeRelationship
};
