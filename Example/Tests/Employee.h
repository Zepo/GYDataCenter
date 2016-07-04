//
//  Employee.h
//  GYDataCenter
//
//  Created by 佘泽坡 on 6/29/16.
//  Copyright © 2016 Zeposhe. All rights reserved.
//

#import <GYDataCenter/GYDataCenter.h>

@class Department;

@interface Employee : GYModelObject

@property (nonatomic, readonly, assign) NSInteger employeeId;
@property (nonatomic, readonly, strong) NSString *name;
@property (nonatomic, readonly, strong) NSDate *dateOfBirth;

@property (nonatomic, readonly, strong) Department *department;

- (instancetype)initWithId:(NSInteger)employeeId
                      name:(NSString *)name
               dateOfBirth:(NSDate *)dateOfBirth
                department:(Department *)department;

@end
