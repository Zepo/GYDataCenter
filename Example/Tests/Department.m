//
//  Department.m
//  GYDataCenter
//
//  Created by 佘泽坡 on 6/29/16.
//  Copyright © 2016 Zeposhe. All rights reserved.
//

#import "Department.h"

@implementation Department

+ (NSString *)dbName {
    return @"GYDataCenterTests";
}

+ (NSString *)tableName {
    return @"Department";
}

+ (NSString *)primaryKey {
    return @"departmentId";
}

+ (NSArray *)persistentProperties {
    static NSArray *properties = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        properties = @[
                       @"departmentId",
                       @"intProperty",
                       @"unsignedProperty",
                       @"shortProperty",
                       @"longProperty",
                       @"unsignedLongProperty",
                       @"longLongProperty",
                       @"unsignedLongLongProperty",
                       @"booleanProperty",
                       @"floatProperty",
                       @"doubleProperty",
                       @"charProperty",
                       @"BOOLProperty",
                       @"stringProperty",
                       @"mutableStringProperty",
                       @"dateProperty",
                       @"dataProperty",
                       @"arrayProperty"
                       ];
    });
    return properties;
}

- (BOOL)isEqual:(id)object {
    Department *other = (Department *)object;
    
    if (self.departmentId != other.departmentId) {
        return NO;
    }
    
    if (self.intProperty != other.intProperty) {
        return NO;
    }
    
    if (self.unsignedProperty != other.unsignedProperty) {
        return NO;
    }
    
    if (self.shortProperty != other.shortProperty) {
        return NO;
    }
    
    if (self.longProperty != other.longProperty) {
        return NO;
    }
    
    if (self.unsignedLongProperty != other.unsignedLongProperty) {
        return NO;
    }
    
    if (self.longLongProperty != other.longLongProperty) {
        return NO;
    }
    
    if (self.unsignedLongLongProperty != other.unsignedLongLongProperty) {
        return NO;
    }
    
    if (self.booleanProperty != other.booleanProperty) {
        return NO;
    }
    
    if (self.floatProperty != other.floatProperty) {
        return NO;
    }
    
    if (self.doubleProperty != other.doubleProperty) {
        return NO;
    }
    
    if (self.charProperty != other.charProperty) {
        return NO;
    }
    
    if (self.BOOLProperty != other.BOOLProperty) {
        return NO;
    }
    
    if ((self.stringProperty || other.stringProperty) &&
        ![self.stringProperty isEqualToString:other.stringProperty]) {
        return NO;
    }
    
    if ((self.mutableStringProperty || other.mutableStringProperty) &&
        ![self.mutableStringProperty isEqualToString:other.mutableStringProperty]) {
        return NO;
    }
    
    if ((self.dateProperty || other.dateProperty) &&
        [self.dateProperty timeIntervalSince1970] != [other.dateProperty timeIntervalSince1970]) {
        return NO;
    }
    
    if ((self.dataProperty || other.dataProperty) &&
        ![self.dataProperty isEqual:other.dataProperty]) {
        return NO;
    }
    
    if ((self.arrayProperty || other.arrayProperty) &&
        ![self.arrayProperty isEqual:other.arrayProperty]) {
        return NO;
    }
    
    return YES;
}

@end
