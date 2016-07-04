//
//  GYModelObject.m
//  GYDataCenter
//
//  Created by 佘泽坡 on 6/24/16.
//  Copyright © 2016 佘泽坡. All rights reserved.
//

#import "GYModelObject.h"

#import "GYDataContext.h"
#import "GYDCUtilities.h"
#import "GYReflection.h"
#import <objc/runtime.h>

@implementation GYModelObject

@synthesize cacheHit = _cacheHit;
@synthesize fault = _fault;
@synthesize saving = _saving;
@synthesize deleted = _deleted;

+ (instancetype)objectWithDictionary:(NSDictionary *)dictionary {
    GYModelObject *object = [[self alloc] init];
    
    NSArray *persistentProperties = [self persistentProperties];
    NSDictionary *propertyTypes = [self propertyTypes];
    for (NSString *key in dictionary.allKeys) {
        if ([persistentProperties containsObject:key]) {
            id value = [dictionary objectForKey:key];
            GYPropertyType propertyType = [[propertyTypes objectForKey:key] unsignedIntegerValue];
            if (propertyType == GYPropertyTypeRelationship) {
                NSAssert([value isKindOfClass:[NSDictionary class]], @"");
                Class propertyClass = [[self propertyClasses] objectForKey:key];
                value = [propertyClass objectWithDictionary:value];
            }
            [object setValue:value forKey:key];
        }
    }
    
    return object;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    Class modelClass = [self class];
    GYModelObject *object = [[modelClass alloc] init];
    
    NSArray *persistentProperties = [modelClass persistentProperties];
    for (NSString *property in persistentProperties) {
        [object setValue:[self valueForKey:property] forKey:property];
    }
    
    return object;
}

#pragma mark - GYModelObjectProtocol

+ (NSString *)dbName {
    NSAssert(NO, @"Should use method of a subclass.");
    return nil;
}

+ (NSString *)tableName {
    NSAssert(NO, @"Should use method of a subclass.");
    return nil;
}

+ (NSString *)primaryKey {
    return nil;
}

+ (NSArray *)persistentProperties {
    NSAssert(NO, @"Should use method of a subclass.");
    return nil;
}

+ (NSDictionary *)propertyTypes {
    static const void * const kPropertyTypesKey = &kPropertyTypesKey;
    NSDictionary *result = objc_getAssociatedObject(self, kPropertyTypesKey);
    if (!result) {
        NSArray *properties = [GYDCUtilities persistentPropertiesForClass:self];
        result = [[NSMutableDictionary alloc] initWithCapacity:properties.count];
        for (NSString *property in properties) {
            GYPropertyType type = [GYDCUtilities propertyTypeOfClass:self propertyName:property];
            [(NSMutableDictionary *)result setObject:@(type) forKey:property];
        }
        objc_setAssociatedObject(self, kPropertyTypesKey, result, OBJC_ASSOCIATION_COPY);
    }
    return result;
}

+ (NSDictionary *)propertyClasses {
    static const void * const kPropertyClassesKey = &kPropertyClassesKey;
    NSDictionary *result = objc_getAssociatedObject(self, kPropertyClassesKey);
    if (!result) {
        result = [[NSMutableDictionary alloc] init];
        NSDictionary *propertyTypes = [self propertyTypes];
        for (NSString *property in propertyTypes.allKeys) {
            GYPropertyType type = [[propertyTypes objectForKey:property] unsignedIntegerValue];
            if (type == GYPropertyTypeRelationship ||
                type == GYPropertyTypeTransformable) {
                NSString *className = [GYReflection propertyTypeOfClass:self propertyName:property];
                Class propertyClass = NSClassFromString(className);
                [(NSMutableDictionary *)result setObject:propertyClass forKey:property];
            }
        }
        objc_setAssociatedObject(self, kPropertyClassesKey, result, OBJC_ASSOCIATION_COPY);
    }
    return result;
}

+ (NSSet *)relationshipProperties {
    static const void * const kRelationshipPropertiesKey = &kRelationshipPropertiesKey;
    NSSet *result = objc_getAssociatedObject(self, kRelationshipPropertiesKey);
    if (!result) {
        result = [[NSMutableSet alloc] init];
        NSDictionary *propertyTypes = [self propertyTypes];
        for (NSString *property in propertyTypes.allKeys) {
            GYPropertyType type = [[propertyTypes objectForKey:property] unsignedIntegerValue];
            if (type == GYPropertyTypeRelationship) {
                [(NSMutableSet *)result addObject:property];
            }
        }
        objc_setAssociatedObject(self, kRelationshipPropertiesKey, result, OBJC_ASSOCIATION_COPY);
    }
    return result;
}

+ (GYCacheLevel)cacheLevel {
    return GYCacheLevelDefault;
}

+ (NSString *)fts {
    return nil;
}

#pragma mark - Dynamic Accessers

+ (BOOL)resolveInstanceMethod:(SEL)aSEL {
    Class class = [self class];
    if ([[self relationshipGetterNames] containsObject:NSStringFromSelector(aSEL)]) {
        SEL getterSelector = @selector(dynamicRelationshipGetter);
        Method getterMethod = class_getInstanceMethod(class, getterSelector);
        class_addMethod(class,
                        aSEL,
                        method_getImplementation(getterMethod),
                        method_getTypeEncoding(getterMethod));
        return YES;
    }
    if ([[self relationshipSetterNames] objectForKey:NSStringFromSelector(aSEL)]) {
        SEL setterSelector = @selector(dynamicRelationshipSetter:);
        Method setterMethod = class_getInstanceMethod(class, setterSelector);
        class_addMethod(class,
                        aSEL,
                        method_getImplementation(setterMethod),
                        method_getTypeEncoding(setterMethod));
        return YES;
    }
    return [super resolveInstanceMethod:aSEL];
}

static const void * const kRelationshipValuesKey = &kRelationshipValuesKey;

- (GYModelObject *)dynamicRelationshipGetter {
    NSMutableDictionary *relationshipValues = objc_getAssociatedObject(self, kRelationshipValuesKey);
    NSString *selectorName = NSStringFromSelector(_cmd);
    GYModelObject *result;
    @synchronized (relationshipValues) {
        result = [relationshipValues objectForKey:selectorName];
        if (result.isFault) {
            Class modelClass = [result class];
            result = [modelClass objectForId:[result valueForKey:[modelClass primaryKey]]];
            if (result) {
                [relationshipValues setObject:result forKey:selectorName];
            }
        }
    }
    return result;
}

- (void)dynamicRelationshipSetter:(GYModelObject *)value {
    NSMutableDictionary *relationshipValues = objc_getAssociatedObject(self, kRelationshipValuesKey);
    if (!relationshipValues) {
        relationshipValues = [[NSMutableDictionary alloc] init];
        objc_setAssociatedObject(self, kRelationshipValuesKey, relationshipValues, OBJC_ASSOCIATION_RETAIN);
    }
    
    NSString *property = [[[self class] relationshipSetterNames] objectForKey:NSStringFromSelector(_cmd)];
    if (value) {
        [relationshipValues setObject:value forKey:property];
    } else {
        [relationshipValues removeObjectForKey:property];
    }
}

+ (NSSet *)relationshipGetterNames {
    static const void * const kRelationshipGetterNamesKey = &kRelationshipGetterNamesKey;
    NSSet *result = objc_getAssociatedObject(self, kRelationshipGetterNamesKey);
    if (!result) {
        result = [[NSMutableSet alloc] init];
        NSDictionary *propertyTypes = [self propertyTypes];
        for (NSString *property in propertyTypes.allKeys) {
            GYPropertyType type = [[propertyTypes objectForKey:property] unsignedIntegerValue];
            if (type == GYPropertyTypeRelationship) {
                [(NSMutableSet *)result addObject:property];
            }
        }
        objc_setAssociatedObject(self, kRelationshipGetterNamesKey, result, OBJC_ASSOCIATION_COPY);
    }
    return result;
}

+ (NSDictionary *)relationshipSetterNames {
    static const void * const kRelationshipSetterNamesKey = &kRelationshipSetterNamesKey;
    NSDictionary *result = objc_getAssociatedObject(self, kRelationshipSetterNamesKey);
    if (!result) {
        result = [[NSMutableDictionary alloc] init];
        NSDictionary *propertyTypes = [self propertyTypes];
        for (NSString *property in propertyTypes.allKeys) {
            GYPropertyType type = [[propertyTypes objectForKey:property] unsignedIntegerValue];
            if (type == GYPropertyTypeRelationship) {
                [(NSMutableDictionary *)result setObject:property forKey:[NSString stringWithFormat:@"set%@:", [property capitalizedString]]];
            }
        }
        objc_setAssociatedObject(self, kRelationshipSetterNamesKey, result, OBJC_ASSOCIATION_COPY);
    }
    return result;
}

#pragma mark - Data Manipulation

+ (GYModelObject *)objectForId:(id)primaryKey {
    return [[GYDataContext sharedInstance] getObject:[self class] properties:nil primaryKey:primaryKey];
}

+ (NSArray *)objectsWhere:(NSString *)where arguments:(NSArray *)arguments {
    return [[GYDataContext sharedInstance] getObjects:[self class] properties:nil where:where arguments:arguments];
}

+ (NSArray *)idsWhere:(NSString *)where arguments:(NSArray *)arguments {
    return [[GYDataContext sharedInstance] getIds:[self class] where:where arguments:arguments];
}

+ (NSNumber *)aggregate:(NSString *)function where:(NSString *)where arguments:(NSArray *)arguments {
    return [[GYDataContext sharedInstance] aggregate:[self class] function:function where:where arguments:arguments];
}

- (void)save {
    [[GYDataContext sharedInstance] saveObject:self];
}

- (void)deleteObject {
    Class<GYModelObjectProtocol> modelClass = [self class];
    [[GYDataContext sharedInstance] deleteObject:modelClass primaryKey:[self valueForKey:[modelClass primaryKey]]];
}

+ (void)deleteObjectsWhere:(NSString *)where arguments:(NSArray *)arguments {
    [[GYDataContext sharedInstance] deleteObjects:[self class] where:where arguments:arguments];
}

- (GYModelObject *)updateObjectSet:(NSDictionary *)set {
    GYModelObject *newObject = [self copy];
    for (NSString *key in set) {
        [newObject setValue:[set objectForKey:key] forKey:key];
    }
    [newObject save];
    return newObject;
}

+ (void)updateObjectsSet:(NSDictionary *)set Where:(NSString *)where arguments:(NSArray *)arguments {
    [[GYDataContext sharedInstance] updateObjects:[self class] set:set where:where arguments:arguments];
}

@end
