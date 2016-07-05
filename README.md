# GYDataCenter
GYDataCenter is an alternative to Core Data for people who like using SQLite directly. 

GYDataCenter is built on top of [FMDB](https://github.com/ccgus/fmdb). It provides object-oriented interfaces while still having the flexibility of using raw SQL. If you want convenience like Core Data and more controll over implementation, performance, queries and indexes, GYDataCenter is a good choice.

# Features
* Well designed object-oriented interfaces.
* Automatically create and update table schemas.
* Use SQL clauses to query data and if you are already familiar with SQL, you can get used to it instantly.
* Well optimized, with features like internal cache, faulting (like that of Core Data), [ANALYZE](https://www.sqlite.org/lang_analyze.html) optimization ... 

# Installation
```
pod 'GYDataCenter'
```

# Usage
1) Define your model classes as normal, except making them subclasses of GYModelObject.
```objc
@interface Employee : GYModelObject
@property (nonatomic, readonly, assign) NSInteger employeeId;
@property (nonatomic, readonly, strong) NSString *name;
@property (nonatomic, readonly, strong) NSDate *dateOfBirth;
@property (nonatomic, readonly, strong) Department *department;
@end
```
2) Implement the following protocol methods. Tell GYDataCenter the database name, table name to use for your model, which property you want to set as primary key and the properties that you want to persist.
```objc
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
    if (!properties) {
        properties = @[
                       @"employeeId",
                       @"name",
                       @"dateOfBirth",
                       @"department"
                       ];
    });
    return properties;
}
```
3) Save and query your model objects as below.
```objc
Employee *employee = ...
[employee save];

employee = [Employee objectForId:@1];
NSArray *employees = [Employee objectsWhere:@"WHERE employeeId < ? ORDER BY employeeId"
                                  arguments:@[ @10 ]];
```

# Automatically Create & Update Table Schemas
As shown above, once you have defined your model classes properly, you are ready to save and query your model objects. You don't have to create the database file or tables yourself. GYDataCenter will do this for you automatically.

Also, after a table is created, if you add more persistent properties, GYDataCenter will update the table schema by adding the new columns for you. However, GYDataCenter **CANNOT** delete or rename an existing column. If you plan to do so, you need to create a new table and migrate the data yourself.

**Indices** are maintained by GYDataCenter too. GYDataCenter is able to create and drop indices automatically, as you implement and modify the following protocol method:
```objc
+ (NSArray *)indices {
    return @[
             @[ @"dateOfBirth" ],
             @[ @"department", @"name" ]
             ];
}
```

**Question: When does GYDataCenter create or update table schemas and how?**

Every time after the app is relaunched, for a given model, GYDataCenter will check if it needs to create or update the table and indices the first time you use GYDataCenter's APIs to manipulate data of that model.
GYDataCenter uses the runtime APIs to query the type of each property, and uses a suitable column type for each property accordingly.

# Where Clause
GYDataCenter uses SQL's where clause to filter records in database. You don't have to learn a whole new set of predicates to use GYDataCenter and doing so maintains the flexibility of SQL. 
```objc
NSArray *employees = [Employee objectsWhere:@"WHERE employeeId < ? ORDER BY employeeId"
                                  arguments:@[ @10 ]];
```
In fact , you can use any clause of SQL that is valid in the place of the where clause.
```objc
NSArray *employees = [Employee objectsWhere:@"ORDER BY employeeId"
                                  arguments:nil];
NSArray *employees = [Employee objectsWhere:@"LIMIT 1"
                                  arguments:nil];
```
And even nested query.
```objc
NSArray *employees = [Employee objectsWhere:@"WHERE department in (SELECT departmentId from department WHERE name = ?)"
                                  arguments:@[ @"Human Resource" ]];
```

It is strongly recommended to bind values to where clauses instead of inlining them. Doing so not only prevents SQL injection, but also increases the chance to reuse SQLite statements. So always use '?' as placeholders for values and pass them in the `arguments` argument.

# Supporting Property Types
The following property types are currently supported:
```objc
int
unsigned
short
long
unsigned long
long long
unsigned long long
bool, BOOL
float
double
char
NSInteger, NSUInteger
NSString, NSMutableString
NSDate
NSData, NSMutableData
Classes that conforms to @protocol NSCoding
Classes that conforms to @protocol GYTransformableProtocol
Subclasses of GYModelObject
```

# Relationship & Faulting
GYDataCenter supports using a model class as the type of a persistent property. Like model **Employee** has a property named department, which is of the type of model **Department**. This is called a **relationship**. GYDataCenter will create a column to store the primary key values of Department in the Emplyee table. Relationship properties are **REQUIRED** to be declared as dynamic in implementation.
```objc
@dynamic department
```

When you save an object of **Employee**, GYDataCenter will **NOT** insert a new record in the **Department** table for the department property. It will only store the primary key value of the department in the new employee record. Thus, if you want to save the department too, you need to do it explicitly.
```objc
[employee save];
[employee.department save];
```

When you query objects of **Employee**, GYDataCenter will not fetch the whole **Department** object for the department property. It will use a placeholder object with only the primary key valid. Once you access the department property, it will be fully realized. This is called **Faulting** and it is done by GYDataCenter automatically. Faulting limits the size of the object graph, reduces the amount of memory your application consumes and speeds up the query.

# Mutable vs. Immutable
GYDataCenter maintains internal cache for model objects. For a given database record, GYDataCenter never has more than one model object in its cache. This means that no matter which thread your code is in, you will get the same copy of model object from GYDataCenter. So your life is easier if your model objects are immutable. If you choose to define your models as mutable, you will need to do the synchronization work to solve issues like race conditions yourself. For example, you can define the properties as atomic:
```objc
@interface Employee : GYModelObject
@property (atomic, assign) NSInteger employeeId;
@property (atomic, strong) NSString *name;
@property (atomic, strong) NSDate *dateOfBirth;
@property (atomic, strong) Department *department;
@end
```

However, it has become more and more a trend to use immutable models to simplify the data flowing through your application. See the [facebook article](https://code.facebook.com/posts/1154141864616569/building-and-managing-ios-model-objects-with-remodel/).

# License

GYDataCenter is available under the MIT license. See the LICENSE file for more info.
