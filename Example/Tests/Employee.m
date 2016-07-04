//
//  Employee.m
//  GYDataCenter
//
//  Created by 佘泽坡 on 6/29/16.
//  Copyright © 2016 Zeposhe. All rights reserved.
//

#import "Employee.h"
#import "Department.h"

@implementation Employee

@dynamic department;

- (instancetype)initWithId:(NSInteger)employeeId
                      name:(NSString *)name
               dateOfBirth:(NSDate *)dateOfBirth
                department:(Department *)department {
    self = [super init];
    if (!self) return nil;
    
    _employeeId = employeeId;
    _name = [name copy];
    _dateOfBirth = dateOfBirth;
    [self setValue:department forKey:@"department"];
    
    return self;
}

+ (NSString *)dbName {
    return @"GYDataCenterTests";
}

+ (NSString *)tableName {
    return @"Employee";
}

+ (NSString *)primaryKey {
    return @"employeeId";
}

+ (NSArray *)persistentProperties {
    static NSArray *properties = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        properties = @[
                       @"employeeId",
                       @"name",
                       @"dateOfBirth",
                       @"department"
                       ];
    });
    return properties;
}

- (BOOL)isEqual:(id)object {
    Employee *other = (Employee *)object;
    
//    if (self.employeeId != other.employeeId) {
//        return NO;
//    }
    
    if ((self.name || other.name) &&
        ![self.name isEqualToString:other.name]) {
        return NO;
    }
    
    if ((self.dateOfBirth || other.dateOfBirth) &&
        [self.dateOfBirth timeIntervalSince1970] != [other.dateOfBirth timeIntervalSince1970]) {
        return NO;
    }
    
    if ((self.department || other.department) &&
        self.department.departmentId != other.department.departmentId) {
        return NO;
    }
    
    return YES;
}

@end
