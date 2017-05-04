//
//  GYDataCenterTests.m
//  GYDataCenter
//
//  Created by 佘泽坡 on 6/29/16.
//  Copyright © 2016 Zeposhe. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "Department.h"
#import "Employee.h"

@interface GYDataCenterTests : XCTestCase

@end

@implementation GYDataCenterTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];
    NSString *dbPath = [documentsDirectory stringByAppendingPathComponent:[[Employee dbName] stringByAppendingPathExtension:@"db"]];
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *srcPath = [bundle pathForResource:@"GYDataCenterTests" ofType:@"db"];
    [[NSFileManager defaultManager] removeItemAtPath:dbPath error:nil];
    [[NSFileManager defaultManager] copyItemAtPath:srcPath toPath:dbPath error:nil];
    
//    NSArray *objects = [self initialEmployees];
//    for (Employee *employee in objects) {
//        [employee save];
//    }
//    [[objects.firstObject department] save];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [[GYDataContext sharedInstance] synchronizeAllData];
    [super tearDown];
}

//- (void)testPerformanceExample {
//    // This is an example of a performance test case.
//    [self measureBlock:^{
//        // Put the code you want to measure the time of here.
//    }];
//}

- (void)testSelectObjects {
    NSArray *initialObjects = [self initialEmployees];
    
    NSString *primaryKey = [Employee primaryKey];
    NSArray *objects = [Employee objectsWhere:[NSString stringWithFormat:@"ORDER BY %@", primaryKey] arguments:nil];
    XCTAssert([objects count] == [initialObjects count], @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
    for (NSUInteger i = 0; i < [objects count]; ++i) {
        XCTAssertEqualObjects([objects objectAtIndex:i], [initialObjects objectAtIndex:i], @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
    }
    XCTAssertEqualObjects([objects.firstObject department], [initialObjects.firstObject department], @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
    
    objects = [Employee objectsWhere:nil arguments:nil];
    XCTAssert([objects count] == [initialObjects count], @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
    
    Employee *firstObject = [initialObjects firstObject];
    objects = [Employee objectsWhere:@"WHERE name=?" arguments:@[ @"Emp1" ]];
    XCTAssertEqualObjects(objects.firstObject, firstObject, @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
    
    id object = [Employee objectForId:[firstObject valueForKey:primaryKey]];
    XCTAssertEqualObjects(object, firstObject, @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
}

- (void)testSelectIds {
    NSArray *initialObjects = [self initialEmployees];
    
    NSString *primaryKey = [Employee primaryKey];
    NSArray *ids = [Employee idsWhere:[NSString stringWithFormat:@"ORDER BY %@", primaryKey] arguments:nil];
    XCTAssert([ids count] == [initialObjects count], @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
    for (NSUInteger i = 0; i < [ids count]; ++i) {
        XCTAssertEqualObjects([ids objectAtIndex:i],
                              [[initialObjects objectAtIndex:i] valueForKey:primaryKey],
                              @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
    }
    
    ids = [Employee idsWhere:@"WHERE (employeeId <= ? AND name <> ?) OR employeeId = ? ORDER BY employeeId DESC"
                   arguments:@[ @2, @"Emp1",  @1]];
    XCTAssert([ids count] == 2, @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
}

- (void)testAggregate {
    NSNumber *count = [Employee aggregate:@"count(*)" where:nil arguments:nil];
    XCTAssert(count.integerValue == 3, @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
    
    count = [Employee aggregate:@"sum(employeeId)" where:@"WHERE employeeId > ?" arguments:@[ @1 ]];
    XCTAssert(count.integerValue == 5, @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
}

- (void)testSave {
    NSDate *date = [NSDate date];
    Employee *employee = [[Employee alloc] initWithId:2
                                                 name:@"New Emp2"
                                          dateOfBirth:date
                                           department:nil];
    [employee save];
    NSArray *objects = [Employee objectsWhere:@"ORDER BY employeeId" arguments:nil];
    XCTAssert([objects count] == 3, @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
    XCTAssertEqualObjects(employee,
                          [objects objectAtIndex:1],
                          @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
    
    employee = [[Employee alloc] initWithId:2
                                       name:@"New Emp2"
                                dateOfBirth:date
                                 department:nil];
    XCTAssertEqualObjects(employee,
                          [objects objectAtIndex:1],
                          @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
    
    Department *department = [Department objectWithDictionary:@{
                                                                @"departmentId" : @2,
                                                                @"intProperty" : @22,
                                                                @"stringProperty" : @"222"
                                                                }];
    employee = [[Employee alloc] initWithId:0           // If primary key value equals to 0, autoincrement will be applied when saved.
                                       name:@"Emp4"
                                dateOfBirth:date
                                 department:department];
    [department save];
    [employee save];
    
    employee = [[Employee alloc] initWithId:4
                                       name:@"Emp4"
                                dateOfBirth:date
                                 department:department];
    objects = [Employee objectsWhere:@"ORDER BY employeeId" arguments:nil];
    XCTAssert([objects count] == 4, @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
    XCTAssertEqualObjects(employee,
                          objects.lastObject,
                          @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
}

- (void)testDelete {
    NSArray *initialObjects = [self initialEmployees];
    [initialObjects.lastObject deleteObject];
    
    NSArray *objects = [Employee objectsWhere:@"ORDER BY employeeId" arguments:nil];
    XCTAssert([objects count] == 2, @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
    for (NSUInteger i = 0; i < [objects count]; ++i) {
        XCTAssertEqualObjects([objects objectAtIndex:i], [initialObjects objectAtIndex:i], @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
    }
    
    [[initialObjects.firstObject department] deleteObject];
    objects = [Employee objectsWhere:@"ORDER BY employeeId" arguments:nil];
    XCTAssert([objects.firstObject department].isDeleted, @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
}

- (void)testUpdate {
    NSArray *initialObjects = [self initialEmployees];
    Employee *employee = initialObjects.firstObject;
    Employee *newEmployee = (Employee *)[employee updateObjectSet:@{ @"name" : @"Employee" }];
    XCTAssert(newEmployee.employeeId == employee.employeeId, @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
    XCTAssertEqualObjects(newEmployee.name, @"Employee", @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
    XCTAssertEqualObjects(newEmployee.department, employee.department, @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
    
    [Employee updateObjectsSet:@{ @"name" : @"Empty" } where:nil arguments:nil];
    NSArray *employees = [Employee objectsWhere:nil arguments:nil];
    for (Employee *employee in employees) {
        XCTAssertEqualObjects(employee.name, @"Empty", @"Test failed: \"%s\"", __PRETTY_FUNCTION__);
    }
}

- (NSArray *)initialEmployees {
    NSArray *array = @[
                       @{
                           @"employeeId" : @1,
                           @"name" : @"Emp1",
                           @"department" : @{
                                   @"departmentId" : @1,
                                   @"intProperty" : @(-1),
                                   @"unsignedProperty" : @22,
                                   @"shortProperty" : @(-333),
                                   @"longProperty" : @(-4444),
                                   @"unsignedLongProperty" : @55555,
                                   @"longLongProperty" : @(-666666),
                                   @"unsignedLongLongProperty" : @7777777,
                                   @"boolProperty" : @(true),
                                   @"floatProperty" : @1.1,
                                   @"doubleProperty" : @(-1.1),
                                   @"charProperty" : @('a'),
                                   @"BOOLProperty" : @NO,
                                   @"stringProperty" : @"abc",
                                   @"mutableStringProperty" : @"def",
                                   @"arrayProperty" : @[ @1, @2, @3 ]
                                   }
                           },
                       @{
                           @"employeeId" : @2,
                           @"name" : @"Emp2",
                           @"department" : @{ @"departmentId" : @1 }
                           },
                       @{
                           @"employeeId" : @3,
                           @"name" : @"Emp3",
                           @"department" : @{ @"departmentId" : @1 }
                           },
                       ];
    
    NSMutableArray *employees = [[NSMutableArray alloc] init];
    for (NSDictionary *dict in array) {
        Employee *employee = [Employee objectWithDictionary:dict];
        [employees addObject:employee];
    }
    return employees;
}

@end
