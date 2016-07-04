//
//  GYDBRunner.m
//  GYDBRunner
//
//  Created by 佘泽坡 on 6/24/16.
//  Copyright © 2016 佘泽坡. All rights reserved.
//

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "This file requires ARC support."
#endif

#import "GYDBRunner.h"

#import "FMDatabaseQueue+Async.h"
#import "GYDCUtilities.h"
#import "GYModelObjectProtocol.h"
#import "GYReflection.h"
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

#ifdef DEBUG
static const BOOL kAutoTransaction = YES;
#else
static const BOOL kAutoTransaction = YES;
#endif

static const double kTransactionTimeInterval = 1;

@interface GYDatabaseInfo : NSObject
@property (nonatomic, strong) FMDatabaseQueue *databaseQueue;
@property (nonatomic, strong) NSMutableSet *updatedTables;
@property (nonatomic, strong) dispatch_source_t timer;
@property (nonatomic, assign) BOOL needCommitTransaction;
@property (nonatomic, assign) NSInteger writeCount;
@end

@implementation GYDatabaseInfo

- (id)init {
    self = [super init];
    if (self) {
        _updatedTables = [[NSMutableSet alloc] init];
    }
    return self;
}

@end

@interface GYDBRunner ()
@property NSMutableDictionary *writeCounts;
@end

@implementation GYDBRunner {
    NSMutableDictionary *_databaseInfos;
}

#pragma mark - Initialization

+ (GYDBRunner *)sharedInstanceWithCacheDelegate:(id<GYDBCache>)delegate {
    static GYDBRunner *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GYDBRunner alloc] initWithCacheDelegate:delegate];
        
        NSData *data = [NSData dataWithContentsOfFile:[self pathForAnalyzeStatistics]];
        if (data.length) {
            sharedInstance.writeCounts = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:nil error:nil];
        } else {
            sharedInstance.writeCounts = [[NSMutableDictionary alloc] init];
        }
    });
    
    sharedInstance.cacheDelegate = delegate;
    
    return sharedInstance;
}

- (id)initWithCacheDelegate:(id<GYDBCache>)delegate {
    if (self = [super init]) {
        _cacheDelegate = delegate;
        _databaseInfos = [[NSMutableDictionary alloc] init];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(synchronizeAllDBs)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Data Manipulation

- (NSArray *)objectsOfClass:(Class<GYModelObjectProtocol>)modelClass
                 properties:(NSArray *)properties
                      where:(NSString *)where
                  arguments:(NSArray *)arguments {
    NSMutableArray *objects = [[NSMutableArray alloc] init];
    
    NSString *columnSql = @"*";
    if ([modelClass fts] && [modelClass primaryKey] && !properties) {
        properties = [GYDCUtilities persistentPropertiesForClass:modelClass];
    }
    if (properties.count) {
        columnSql = [self columnSqlForClass:modelClass properties:properties withPrefix:NO];
    }
    
    NSMutableString *sql = [[NSMutableString alloc] initWithFormat:@"SELECT %@ FROM %@", columnSql, [modelClass tableName]];
    if (where) {
        [sql appendFormat:@" %@", where];
    }
    
    NSUInteger length = properties.count;
    if (!length) {
        length = [GYDCUtilities persistentPropertiesForClass:modelClass].count;
    }
    NSMutableArray *indexedProperties = [[NSMutableArray alloc] initWithCapacity:length];
    
    GYDatabaseInfo *databaseInfo = [self databaseInfoForClass:modelClass];
    [databaseInfo.databaseQueue syncInDatabase:^(FMDatabase *db) {
        FMResultSet *resultSet = [db executeQuery:sql withArgumentsInArray:arguments];
        while ([resultSet next]) {
            id object = [self objectOfClass:modelClass resultSet:resultSet range:NSMakeRange(0, length) properties:indexedProperties];
            [objects addObject:object];
        }
    }];
    
    return objects;
}

- (NSArray *)objectsOfClass:(Class<GYModelObjectProtocol>)leftClass
                 properties:(NSArray *)leftProperties
                      class:(Class<GYModelObjectProtocol>)rightClass
                 properties:(NSArray *)rightProperties
                   joinType:(GYSQLJoinType)joinType
              joinCondition:(NSString *)joinCondition
                      where:(NSString *)where
                  arguments:(NSArray *)arguments {
    NSAssert([[leftClass dbName] isEqualToString:[rightClass dbName]], @"Tables in join sql should come from the same db");
    
    NSString *columnSql = @"*";
    if (leftProperties.count || rightProperties.count) {
        NSString *leftColumnSql = [self columnSqlForClass:leftClass properties:leftProperties withPrefix:YES];
        NSString *rightColumnSql = [self columnSqlForClass:rightClass properties:rightProperties withPrefix:YES];
        columnSql = [[NSString alloc] initWithFormat:@"%@,%@", leftColumnSql, rightColumnSql];
    }
    
    NSString *join = @"INNER JOIN";
    switch (joinType) {
        case GYSQLJoinTypeInner:
            break;
        case GYSQLJoinTypeLeft:
            join = @"LEFT OUTER JOIN";
            break;
        case GYSQLJoinTypeCross:
            NSAssert(joinCondition.length == 0, @"Cross join cannot have join condition");
            join = @"CROSS JOIN";
            break;
        default:
            NSAssert(NO, @"Invalid join type");
            break;
    }
    
    NSMutableString *sql = [[NSMutableString alloc] initWithFormat:@"SELECT %@ FROM %@ %@ %@ ON %@", columnSql, [leftClass tableName], join, [rightClass tableName], joinCondition];
    if (where) {
        [sql appendFormat:@" %@", where];
    }
    
    NSMutableArray *leftObjects = [[NSMutableArray alloc] init];
    NSMutableArray *rightObjects = [[NSMutableArray alloc] init];
    NSUInteger leftLength = leftProperties.count;
    if (!leftLength) {
        leftLength = [GYDCUtilities persistentPropertiesForClass:leftClass].count;
    }
    NSMutableArray *leftIndexedProperties = [[NSMutableArray alloc] initWithCapacity:leftLength];
    NSUInteger rightLength = rightProperties.count;
    if (!rightLength) {
        rightLength = [GYDCUtilities persistentPropertiesForClass:rightClass].count;
    }
    NSMutableArray *rightIndexedProperties = [[NSMutableArray alloc] initWithCapacity:rightLength];
    
    GYDatabaseInfo *databaseInfo = [self databaseInfoForClass:leftClass];
    [self databaseInfoForClass:rightClass];
    [databaseInfo.databaseQueue syncInDatabase:^(FMDatabase *db) {
        FMResultSet *resultSet = [db executeQuery:sql withArgumentsInArray:arguments];
        while ([resultSet next]) {
            [leftObjects addObject:[self objectOfClass:leftClass resultSet:resultSet range:NSMakeRange(0, leftLength) properties:leftIndexedProperties]];
            [rightObjects addObject:[self objectOfClass:rightClass resultSet:resultSet range:NSMakeRange(leftLength, rightLength) properties:rightIndexedProperties]];
        }
    }];
    
    return @[ leftObjects, rightObjects ];
}

- (NSString *)columnSqlForClass:(Class<GYModelObjectProtocol>)modelClass
                     properties:(NSArray *)properties
                     withPrefix:(BOOL)withPrefix {
    if (!properties) {
        properties = [GYDCUtilities persistentPropertiesForClass:modelClass];
    }
    
    NSMutableString *columnSql = [[NSMutableString alloc] init];
    NSString *tableName = [modelClass tableName];
    for (NSUInteger i = 0; i < [properties count]; ++i) {
        NSString *property = [properties objectAtIndex:i];
        NSAssert([[GYDCUtilities persistentPropertiesForClass:modelClass] containsObject:property], @"Property %@ is not persistent", property);
        NSString *column = [GYDCUtilities columnForClass:modelClass property:property];
        if (i) {
            if (withPrefix) {
                [columnSql appendFormat:@",%@.%@", tableName, column];
            } else {
                [columnSql appendFormat:@",%@", column];
            }
        } else {
            if (withPrefix) {
                [columnSql appendFormat:@"%@.%@", tableName, column];
            } else {
                [columnSql appendFormat:@"%@", column];
            }
        }
    }
    
    return columnSql;
}

- (id)objectOfClass:(Class<GYModelObjectProtocol>)modelClass resultSet:(FMResultSet *)resultSet range:(NSRange)range properties:(NSMutableArray *)properties {
    id object = nil;
    for (NSInteger i = range.location; i < range.location + range.length; ++i) {
        NSInteger index = i - range.location;
        if (index >= properties.count) {
            NSString *column = [resultSet columnNameForIndex:(int)i];
            [properties addObject:[GYDCUtilities propertyForClass:modelClass column:column]];
        }
        NSString *property = [properties objectAtIndex:index];
        
        if (index == 0 && [property isEqualToString:[modelClass primaryKey]]) {
            id value = [self valueForClass:modelClass property:property resultSet:resultSet index:(int)i];
            if (value) {
                id<GYModelObjectProtocol> cache = [_cacheDelegate objectOfClass:modelClass id:value];
                if (cache && !cache.isFault) {
                    return cache;
                }
                if (!cache) {
                    object = [[(Class)modelClass alloc] init];
                    [object setValue:value forKey:property];
                } else {
                    object = cache;
                    [object setValue:@NO forKey:@"fault"];
                }
            }
        } else {
            if (!object) {
                object = [[(Class)modelClass alloc] init];
            }
            [self setProperty:property ofObject:object withResultSet:resultSet index:(int)i];
        }
    }
    return object;
}

- (void)setProperty:(NSString *)property ofObject:(id)modelObject withResultSet:(FMResultSet *)resultSet index:(int)index {
    id value = [self valueForClass:[modelObject class] property:property resultSet:resultSet index:index];
    if (value) {
        [modelObject setValue:value forKey:property];
    }
}

- (id)valueForClass:(Class<GYModelObjectProtocol>)modelClass property:(NSString *)property resultSet:(FMResultSet *)resultSet index:(int)index {
    GYPropertyType propertyType = [[[modelClass propertyTypes] objectForKey:property] unsignedIntegerValue];
    Class propertyClass;
    if (propertyType == GYPropertyTypeRelationship) {
        propertyClass = [[modelClass propertyClasses] objectForKey:property];
        propertyType = [[[propertyClass propertyTypes] objectForKey:[propertyClass primaryKey]] unsignedIntegerValue];
    }
    
    id value = nil;
    if (![self needSerializationForType:propertyType]) {
        if (propertyType == GYPropertyTypeDate) {
            value = [resultSet dateForColumnIndex:index];
        } else {
            value = [resultSet objectForColumnIndex:index];
        }
    } else {
        NSData *data = [resultSet dataForColumnIndex:index];
        if (data.length) {
            if (propertyType == GYPropertyTypeTransformable) {
                Class propertyClass = [[modelClass propertyClasses] objectForKey:property];
                value = [propertyClass reverseTransformedValue:data];
            } else {
                value = [self valueAfterDecodingData:data];
            }
            if (!value) {
                NSAssert(NO, @"database=%@, table=%@, property=%@", [modelClass dbName], [modelClass tableName], property);
            }
        }
    }
    if ([value isKindOfClass:[NSNull class]]) {
        value = nil;
    }
    
    if (propertyClass) {
        id cache = [_cacheDelegate objectOfClass:propertyClass id:value];
        if (!cache) {
            cache = [[(Class)propertyClass alloc] init];
            [cache setValue:value forKey:[propertyClass primaryKey]];
            [cache setValue:@YES forKey:@"fault"];
            [_cacheDelegate cacheObject:cache];
        }
        value = cache;
    }
    return value;
}

- (BOOL)needSerializationForType:(GYPropertyType)type {
    if ([self mapsIntegerForType:type] ||
        [self mapsRealForType:type] ||
        [self mapsTextForType:type] ||
        type == GYPropertyTypeData ||
        type == GYPropertyTypeRelationship) {
        return NO;
    } else {
        return YES;
    }
}

- (id)valueAfterDecodingData:(NSData *)data {
    id value = nil;
    @try {
        value = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    }
    @catch (NSException *exception) {
        value = nil;
    }
    @finally {
        
    }
    return value;
}

- (NSArray *)idsOfClass:(Class<GYModelObjectProtocol>)modelClass
                  where:(NSString *)where
              arguments:(NSArray *)arguments {
    if (![modelClass primaryKey]) {
        return nil;
    }
    
    NSMutableArray *ids = [[NSMutableArray alloc] init];
    
    NSString *primaryKeyColumn = [GYDCUtilities columnForClass:modelClass property:[modelClass primaryKey]];
    NSMutableString *sql = [[NSMutableString alloc] initWithFormat:@"SELECT %@ FROM %@", primaryKeyColumn, [modelClass tableName]];
    if (where) {
        [sql appendFormat:@" %@", where];
    }
    
    GYDatabaseInfo *databaseInfo = [self databaseInfoForClass:modelClass];
    [databaseInfo.databaseQueue syncInDatabase:^(FMDatabase *db) {
        FMResultSet *resultSet = [db executeQuery:sql withArgumentsInArray:arguments];
        while ([resultSet next]) {
            id objectId = [resultSet objectForColumnName:primaryKeyColumn];
            [ids addObject:objectId];
        }
    }];
    
    return ids;
}

- (NSNumber *)aggregateOfClass:(Class<GYModelObjectProtocol>)modelClass
                      function:(NSString *)function
                         where:(NSString *)where
                     arguments:(NSArray *)arguments {
    __block NSNumber *result = nil;
    
    NSMutableString *sql = [[NSMutableString alloc] initWithFormat:@"SELECT %@ FROM %@", function, [modelClass tableName]];
    if (where) {
        [sql appendFormat:@" %@", where];
    }
    
    GYDatabaseInfo *databaseInfo = [self databaseInfoForClass:modelClass];
    [databaseInfo.databaseQueue syncInDatabase:^(FMDatabase *db) {
        FMResultSet *resultSet = [db executeQuery:sql withArgumentsInArray:arguments];
        if ([resultSet next]) {
            result = [resultSet objectForColumnIndex:0];
        }
        [resultSet close];
    }];
    if (![result isKindOfClass:[NSNull class]]) {
        return result;
    }
    return nil;
}

- (void)saveObject:(id<GYModelObjectProtocol>)object {
    if (!object) {
        NSAssert(NO, @"object cannot be nil");
        return;
    }
    
    Class<GYModelObjectProtocol> modelClass = [object class];
    BOOL hasPrimaryKey = [self isPrimaryKeyProvidedWithObject:object];
    
    NSString *sql = nil;
    NSArray *properties = nil;
    [self getSql:&sql properties:&properties forClass:modelClass withPrimaryKey:hasPrimaryKey];
    
    NSMutableArray *arguments = [[NSMutableArray alloc] initWithCapacity:properties.count];
    for (NSString *property in properties) {
        [arguments addObject:[self valueOfProperty:property ofObject:object]];
    }
    
    GYDatabaseInfo *databaseInfo = [self databaseInfoForClass:modelClass];
    if (!hasPrimaryKey) {
        [databaseInfo.databaseQueue syncInDatabase:^(FMDatabase *db) {
            [self recordWriteOperationForDatabaseInfo:databaseInfo];
            [db executeUpdate:sql withArgumentsInArray:arguments];
            [(id)object setValue:@([db lastInsertRowId]) forKey:[modelClass primaryKey]];
        }];
    } else {
        [databaseInfo.databaseQueue asyncInDatabase:^(FMDatabase *db) {
            [self recordWriteOperationForDatabaseInfo:databaseInfo];
            [db executeUpdate:sql withArgumentsInArray:arguments];
        }];
    }
}

- (void)getSql:(NSString **)sql properties:(NSArray **)properties forClass:(Class<GYModelObjectProtocol>)modelClass withPrimaryKey:(BOOL)hasPrimaryKey {
    NSMutableArray *tempProperties = [[GYDCUtilities persistentPropertiesForClass:modelClass] mutableCopy];
    if (!hasPrimaryKey && [modelClass primaryKey]) {
        [tempProperties removeObject:[modelClass primaryKey]];
    }
    *properties = tempProperties;
    
    static const void * const kSaveSqlKey = &kSaveSqlKey;
    static const void * const kSaveSqlForAutoIncreamentKey = &kSaveSqlForAutoIncreamentKey;
    if (hasPrimaryKey) {
        *sql = objc_getAssociatedObject(modelClass, kSaveSqlKey);
    } else {
        *sql = objc_getAssociatedObject(modelClass, kSaveSqlForAutoIncreamentKey);
    }
    
    if (!*sql) {
        NSMutableArray *columns = [[NSMutableArray alloc] init];
        NSMutableArray *questionMarks = [[NSMutableArray alloc] init];
        for (NSString *property in *properties) {
            [columns addObject:[GYDCUtilities columnForClass:modelClass property:property]];
            [questionMarks addObject:@"?"];
        }
        
        *sql = [NSString stringWithFormat:@"REPLACE INTO %@ (%@) VALUES (%@)",
                [modelClass tableName],
                [columns componentsJoinedByString:@","],
                [questionMarks componentsJoinedByString:@","]];
        
        if (hasPrimaryKey) {
            objc_setAssociatedObject(modelClass, kSaveSqlKey, *sql, OBJC_ASSOCIATION_COPY_NONATOMIC);
        } else {
            objc_setAssociatedObject(modelClass, kSaveSqlForAutoIncreamentKey, *sql, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
    }
}

- (BOOL)isPrimaryKeyProvidedWithObject:(id<GYModelObjectProtocol>)object {
    NSString *primaryKey = [[object class] primaryKey];
    if (!primaryKey) {
        return YES;
    }
    
    id value = [(id)object valueForKey:primaryKey];
    GYPropertyType propertyType = [[[[object class] propertyTypes] objectForKey:primaryKey] unsignedIntegerValue];
    if ([self mapsIntegerForType:propertyType]) {
        if (!value) {
            return NO;
        }
        NSAssert([value isKindOfClass:[NSNumber class]], @"Something is wrong");
        if ([((NSNumber *)value) isEqualToNumber:@(0)]) {
            return NO;
        } else {
            return YES;
        }
    } else {
        NSAssert(value, @"DB Error: Auto increament is supported for interger type only");
        return YES;
    }
}

- (id)valueOfProperty:(NSString *)property ofObject:(id)modelObject {
    Class modelClass = [modelObject class];
    GYPropertyType propertyType = [[[modelClass propertyTypes] objectForKey:property] unsignedIntegerValue];
    
    id value = nil;
    if (propertyType == GYPropertyTypeRelationship) {
        value = [modelObject valueForKey:property];
        if (value) {
            Class propertyClass = [[modelClass propertyClasses] objectForKey:property];
            value = [value valueForKey:[propertyClass primaryKey]];
        }
    } else if (![self needSerializationForType:propertyType]) {
        value = [modelObject valueForKey:property];
    } else {
        id propertyValue = [modelObject valueForKey:property];
        if (propertyValue) {
            if (propertyType == GYPropertyTypeTransformable) {
                Class propertyClass = [[modelClass propertyClasses] objectForKey:property];
                value = [propertyClass transformedValue:propertyValue];
            } else if ([propertyValue conformsToProtocol:@protocol(NSCoding)]) {
                value = [self dataAfterEncodingObject:propertyValue];
            } else {
                NSAssert(0, @"DB Error: Don't know how to store property '%@'.", property);
            }
        }
    }
    
    if (!value) {
        value = [NSNull null];
    }
    
    return value;
}

- (NSData *)dataAfterEncodingObject:(id<NSCoding>)object {
    return [NSKeyedArchiver archivedDataWithRootObject:object];
}

- (void)deleteClass:(Class<GYModelObjectProtocol>)modelClass
              where:(NSString *)where
          arguments:(NSArray *)arguments {
    GYDatabaseInfo *databaseInfo = [self databaseInfoForClass:modelClass];
    [databaseInfo.databaseQueue asyncInDatabase:^(FMDatabase *db) {
        NSString *sql = nil;
        if (where) {
            sql = [NSString stringWithFormat:@"DELETE FROM %@ %@", [modelClass tableName], where];
        } else {
            sql = [NSString stringWithFormat:@"DELETE FROM %@", [modelClass tableName]];
        }
        
        [self recordWriteOperationForDatabaseInfo:databaseInfo];
        [db executeUpdate:sql withArgumentsInArray:arguments];
    }];
}

- (void)updateClass:(Class<GYModelObjectProtocol>)modelClass
                set:(NSDictionary *)set
              where:(NSString *)where
          arguments:(NSArray *)arguments {
    NSAssert([set count], @"DB Error: Argument 'set' should not be nil.");
    
    GYDatabaseInfo *databaseInfo = [self databaseInfoForClass:modelClass];
    [databaseInfo.databaseQueue asyncInDatabase:^(FMDatabase *db) {
        NSMutableString *setSql = [[NSMutableString alloc] initWithString:@"SET "];
        NSMutableArray *values = [[NSMutableArray alloc] init];
        id<GYModelObjectProtocol> modelObject = [[(Class)modelClass alloc] init];
        NSArray *allKeys = set.allKeys;
        NSUInteger count = [allKeys count];
        for (NSUInteger i = 0; i < count; ++i) {
            if (i) {
                [setSql appendString:@","];
            }
            NSString *key = [allKeys objectAtIndex:i];
            [setSql appendFormat:@"%@=?", [GYDCUtilities columnForClass:modelClass property:key]];
            [(id)modelObject setValue:[set objectForKey:key] forKey:key];
            [values addObject:[self valueOfProperty:key ofObject:modelObject]];
        }
        
        NSMutableString *sql = [[NSMutableString alloc] initWithFormat:@"UPDATE %@ %@", [modelClass tableName], setSql];
        if (where) {
            [sql appendFormat:@" %@", where];
        }
        [values addObjectsFromArray:arguments];
        
        [self recordWriteOperationForDatabaseInfo:databaseInfo];
        [db executeUpdate:sql withArgumentsInArray:values];
    }];
}

- (void)recordWriteOperationForDatabaseInfo:(GYDatabaseInfo *)databaseInfo {
    if (databaseInfo.timer) {
        databaseInfo.needCommitTransaction = YES;
    }
    ++databaseInfo.writeCount;
}

- (void)inTransaction:(dispatch_block_t)block
               dbName:(NSString *)dbName {
    GYDatabaseInfo *databaseInfo = [self databaseInfoForDbName:dbName];
    [databaseInfo.databaseQueue syncInDatabase:^(FMDatabase *db) {
        if (databaseInfo.timer) {
            dispatch_suspend(databaseInfo.timer);
            [db commit];
            databaseInfo.needCommitTransaction = NO;
        }
        
        [db beginTransaction];
        block();
        [db commit];
        
        if (databaseInfo.timer) {
            [db beginTransaction];
            dispatch_resume(databaseInfo.timer);
        }
    }];
}

- (void)vacuumAllDBs {
    NSArray *databaseInfos;
    @synchronized(_databaseInfos) {
        databaseInfos = _databaseInfos.allValues;
    }
    for (GYDatabaseInfo *databaseInfo in databaseInfos) {
        [databaseInfo.databaseQueue syncInDatabase:^(FMDatabase *db) {
            if (databaseInfo.timer) {
                dispatch_suspend(databaseInfo.timer);
                [db commit];
                databaseInfo.needCommitTransaction = NO;
            }
            [db executeStatements:@"VACUUM"];
            if (databaseInfo.timer) {
                [db beginTransaction];
                dispatch_resume(databaseInfo.timer);
            }
        }];
    }
}

- (void)synchronizeAllDBs {
    @synchronized(_databaseInfos) {
        [self analyzeAllDBs];
        
        for (NSString *dbName in _databaseInfos.allKeys) {
            [self synchronizeDB:dbName];
        }
    }
}

- (void)synchronizeDB:(NSString *)dbName {
    @synchronized(_databaseInfos) {
        GYDatabaseInfo *databaseInfo = [_databaseInfos objectForKey:dbName];
        if (databaseInfo.timer) {
            dispatch_suspend(databaseInfo.timer);
            [databaseInfo.databaseQueue syncInDatabase:^(FMDatabase *db) {
                [db commit];
            }];
        }
        [databaseInfo.databaseQueue close];
        [_databaseInfos removeObjectForKey:dbName];
    }
}

- (void)analyzeAllDBs {
    @synchronized(_databaseInfos) {
        for (NSString *dbName in _databaseInfos.allKeys) {
            GYDatabaseInfo *databaseInfo = [_databaseInfos objectForKey:dbName];
            [databaseInfo.databaseQueue syncInDatabase:^(FMDatabase *db) {
                if (databaseInfo.writeCount >= 500) {
                    [db executeStatements:@"ANALYZE;ANALYZE sqlite_master"];
                    databaseInfo.writeCount = 0;
                }
                [self.writeCounts setObject:@(databaseInfo.writeCount) forKey:dbName];
            }];
        }
        
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:self.writeCounts
                                                                  format:NSPropertyListBinaryFormat_v1_0
                                                                 options:0
                                                                   error:nil];
        [data writeToFile:[GYDBRunner pathForAnalyzeStatistics] atomically:YES];
    }
}

#pragma mark - Data Definition

- (GYDatabaseInfo *)databaseInfoForClass:(Class<GYModelObjectProtocol>)modelClass {
    GYDatabaseInfo *databaseInfo = [self databaseInfoForDbName:[modelClass dbName]];
    
    @synchronized(databaseInfo.updatedTables) {
        if (![databaseInfo.updatedTables containsObject:[modelClass tableName]]) {
            if ([self isTable:[modelClass tableName] existsWithDatabaseQueue:databaseInfo.databaseQueue]) {
                [self updateTableSchemaForClass:modelClass databaseQueue:databaseInfo.databaseQueue];
                [self updateIndicesForClass:modelClass databaseQueue:databaseInfo.databaseQueue];
            } else {
                [self createTableForClass:modelClass databaseQueue:databaseInfo.databaseQueue];
                [self createIndicesForClass:modelClass databaseQueue:databaseInfo.databaseQueue];
            }
            [databaseInfo.updatedTables addObject:[modelClass tableName]];
        }
    }
    
    return databaseInfo;
}

- (BOOL)isTable:(NSString *)tableName existsWithDatabaseQueue:(FMDatabaseQueue *)databaseQueue {
    __block BOOL result = NO;
    NSString *sql = @"SELECT tbl_name FROM sqlite_master WHERE type='table' AND tbl_name=?";
    [databaseQueue syncInDatabase:^(FMDatabase *db) {
        FMResultSet *resultSet = [db executeQuery:sql withArgumentsInArray:@[ tableName ]];
        if ([resultSet next]) {
            result = YES;
        }
        [resultSet close];
    }];
    return result;
}

- (void)updateTableSchemaForClass:(Class<GYModelObjectProtocol>)modelClass
                    databaseQueue:(FMDatabaseQueue *)databaseQueue {
    NSArray *existingColumns = [self columnsForTable:[modelClass tableName] databaseQueue:databaseQueue];
    NSArray *columns = [GYDCUtilities allColumnsForClass:modelClass];
    
    if ([self isVirtualTableForClass:modelClass]) {
        NSAssert([modelClass primaryKey] ? existingColumns.count == columns.count - 1 : existingColumns.count == columns.count,
                 @"Cannot ALTER virtual table.");
        return;
    } else {
        NSAssert(existingColumns.count <= columns.count,
                 @"DB Error: There are %lu columns existing in table '%@' and %lu columns are expected.",
                 ((unsigned long)[existingColumns count]),
                 [modelClass tableName],
                 ((unsigned long)[columns count]));
    }
    
    for (NSString *existingColumn in existingColumns) {
        if (![columns containsObject:existingColumn]) {
            NSAssert(0, @"DB Error: No mapping for existing column '%@'", existingColumn);
        }
    }
    
    if ([existingColumns count] < [columns count]) {
        for (NSString *column in columns) {
            if (![existingColumns containsObject:column]) {
                NSString *sql = [NSString stringWithFormat:@"ALTER TABLE %@ ADD COLUMN %@",
                                 [modelClass tableName],
                                 [self columnDefinitionForClass:modelClass property:[GYDCUtilities propertyForClass:modelClass column:column]]];
                [databaseQueue asyncInDatabase:^(FMDatabase *db) {
                    [db executeUpdate:sql];
                }];
                NSLog(@"DB Log: Add column '%@' for table '%@'.", column, [modelClass tableName]);
            }
        }
    }
}

- (NSArray *)columnsForTable:(NSString *)tableName databaseQueue:(FMDatabaseQueue *)databaseQueue {
    NSMutableArray *columns = [[NSMutableArray alloc] init];
    [databaseQueue syncInDatabase:^(FMDatabase *db) {
        FMResultSet *resultSet = [db executeQuery:[NSString stringWithFormat:@"PRAGMA table_info(%@)", tableName]];
        while ([resultSet next]) {
            [columns addObject:[resultSet stringForColumn:@"name"]];
        }
    }];
    return columns;
}

- (void)updateIndicesForClass:(Class<GYModelObjectProtocol>)modelClass
                databaseQueue:(FMDatabaseQueue *)databaseQueue {
    if (![(Class)modelClass respondsToSelector:@selector(indices)])
        return;
    
    NSMutableSet *existingIndices = [self indicesForTable:[modelClass tableName] databaseQueue:databaseQueue];
    
    for (NSArray *index in [modelClass indices]) {
        NSString *indexName = [self indexNameForTable:[modelClass tableName] properties:index];
        if (![existingIndices containsObject:indexName]) {
            [self createIndexForClass:modelClass Properties:index databaseQueue:databaseQueue];
        } else {
            [existingIndices removeObject:indexName];
        }
    }
    
    for (NSString *indexName in existingIndices) {
        [self dropIndex:indexName databaseQueue:databaseQueue];
    }
}

- (NSMutableSet *)indicesForTable:(NSString *)tableName databaseQueue:(FMDatabaseQueue *)databaseQueue {
    NSMutableSet *indices = [[NSMutableSet alloc] init];
    NSString *sql = [[NSString alloc] initWithFormat:@"PRAGMA index_list(%@)", tableName];
    [databaseQueue syncInDatabase:^(FMDatabase *db) {
        FMResultSet *resultSet = [db executeQuery:sql];
        while ([resultSet next]) {
            NSString *indexName = [resultSet stringForColumn:@"name"];
            if (![indexName hasPrefix:@"sqlite_autoindex_"]) {
                [indices addObject:[resultSet stringForColumn:@"name"]];
            }
        }
    }];
    return indices;
}

- (void)dropIndex:(NSString *)indexName databaseQueue:(FMDatabaseQueue *)databaseQueue {
    [databaseQueue asyncInDatabase:^(FMDatabase *db) {
        NSString *sql = [[NSString alloc] initWithFormat:@"DROP INDEX %@", indexName];
        [db executeUpdate:sql];
    }];
}

- (void)createTableForClass:(Class<GYModelObjectProtocol>)modelClass
              databaseQueue:(FMDatabaseQueue *)databaseQueue {
    NSString *sql;
    if ([self isVirtualTableForClass:modelClass]) {
        sql = [self sqlForCreateVirtualTableForClass:modelClass];
    } else {
        sql = [self sqlForCreateTableForClass:modelClass];
    }
    
    [databaseQueue asyncInDatabase:^(FMDatabase *db) {
        [db executeUpdate:sql];
        NSLog(@"DB Log: Create table '%@' for database %@.",
              [modelClass tableName],
              [modelClass dbName]);
    }];
}

- (NSString *)sqlForCreateVirtualTableForClass:(Class<GYModelObjectProtocol>)modelClass {
    NSMutableArray *columns = [[GYDCUtilities allColumnsForClass:modelClass] mutableCopy];
    [columns removeObject:[GYDCUtilities columnForClass:modelClass property:[modelClass primaryKey]]];
    if ([(Class)modelClass respondsToSelector:@selector(tokenize)]) {
        NSString *tokenize = [modelClass tokenize];
        if (tokenize.length) {
            [columns addObject:[NSString stringWithFormat:@"tokenize=%@", tokenize]];
        }
    }
    
    return [NSString stringWithFormat:@"CREATE VIRTUAL TABLE %@ USING %@(%@)",
            [modelClass tableName],
            [modelClass fts],
            [columns componentsJoinedByString:@","]];
}

- (NSString *)sqlForCreateTableForClass:(Class<GYModelObjectProtocol>)modelClass {
    NSArray *columnDefinitions = [self columnDefinitionsForClass:modelClass];
    return [NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (%@)",
            [modelClass tableName],
            [columnDefinitions componentsJoinedByString:@","]];
}

- (NSArray *)columnDefinitionsForClass:(Class<GYModelObjectProtocol>)modelClass {
    NSMutableArray *columnDefinitions = [[NSMutableArray alloc] init];
    for (NSString *property in [self sortedPropertiesForClass:modelClass]) {
        [columnDefinitions addObject:[self columnDefinitionForClass:modelClass property:property]];
    }
    return columnDefinitions;
}

- (NSArray *)sortedPropertiesForClass:(Class<GYModelObjectProtocol>)modelClass {
    NSString *primaryKey = [modelClass primaryKey];
    NSMutableArray *properties = [[GYDCUtilities persistentPropertiesForClass:modelClass] mutableCopy];
    if (primaryKey) {
        [properties removeObject:primaryKey];
    }
    [properties sortUsingComparator:^NSComparisonResult(NSString *obj1, NSString *obj2) {
        return [obj1 compare:obj2];
    }];
    if (primaryKey) {
        [properties insertObject:primaryKey atIndex:0];
    }
    return properties;
}

- (NSString *)columnDefinitionForClass:(Class<GYModelObjectProtocol>)modelClass property:(NSString *)property {
    NSString *column = [GYDCUtilities columnForClass:modelClass property:property];
    
    NSMutableString *definition = nil;
    GYPropertyType propertyType = [[[modelClass propertyTypes] objectForKey:property] unsignedIntegerValue];
    
    if (propertyType == GYPropertyTypeRelationship) {
        NSAssert(![property isEqualToString:[modelClass primaryKey]], @"");
        Class<GYModelObjectProtocol> propertyClass = [[modelClass propertyClasses] objectForKey:property];
        NSString *primaryKey = [propertyClass primaryKey];
        if (primaryKey) {
            propertyType = [[[propertyClass propertyTypes] objectForKey:primaryKey] unsignedIntegerValue];
        } else {
            propertyType = GYPropertyTypeInteger;
        }
    }
    
    if ([self mapsIntegerForType:propertyType]) {
        if ([property isEqualToString:[modelClass primaryKey]]) {
            definition = [NSMutableString stringWithFormat:@"%@ INTEGER PRIMARY KEY AUTOINCREMENT", column];
        } else {
            definition = [NSMutableString stringWithFormat:@"%@ INTEGER", column];
        }
    } else if ([self mapsRealForType:propertyType]) {
        if ([property isEqualToString:[modelClass primaryKey]]) {
            definition = [NSMutableString stringWithFormat:@"%@ REAL PRIMARY KEY", column];
        } else {
            definition = [NSMutableString stringWithFormat:@"%@ REAL", column];
        }
    } else if ([self mapsTextForType:propertyType]) {
        if ([property isEqualToString:[modelClass primaryKey]]) {
            definition = [NSMutableString stringWithFormat:@"%@ TEXT PRIMARY KEY", column];
        } else {
            definition = [NSMutableString stringWithFormat:@"%@ TEXT", column];
        }
    } else {
        if ([property isEqualToString:[modelClass primaryKey]]) {
            // In SQLite, any column can be set as primary key regardless of its type.
            // However, supporting it for BLOB type incurs complexity and
            // I believe most of us, if not all, will never need such a feature.
            NSAssert(0, @"DB Error: Property '%@' could not be used as primary key.", property);
        } else {
            definition = [NSMutableString stringWithFormat:@"%@ BLOB", column];
        }
    }
    
    if ([(Class)modelClass respondsToSelector:@selector(defaultValues)]) {
        NSDictionary *defaultValues = [modelClass defaultValues];
        id defaultValue = [defaultValues objectForKey:property];
        if (defaultValue) {
            NSAssert(![property isEqualToString:[modelClass primaryKey]], @"DB Error: Primary key cannot has default value.");
            if ([defaultValue isKindOfClass:[NSString class]]) {
                [definition appendFormat:@" DEFAULT '%@'", defaultValue];
            } else {
                [definition appendFormat:@" DEFAULT %@", defaultValue];
            }
        }
    }
    
    return definition;
}

- (void)createIndicesForClass:(Class<GYModelObjectProtocol>)modelClass
                databaseQueue:(FMDatabaseQueue *)databaseQueue {
    if (![(Class)modelClass respondsToSelector:@selector(indices)])
        return;
    
    if ([self isVirtualTableForClass:modelClass]) {
        NSAssert([modelClass indices].count == 0, @"Cannot create indices for virtual table.");
        return;
    }
    
    NSArray *indices = [modelClass indices];
    for (NSArray *index in indices) {
        [self createIndexForClass:modelClass Properties:index databaseQueue:databaseQueue];
    }
}

- (void)createIndexForClass:(Class<GYModelObjectProtocol>)modelClass
                 Properties:(NSArray *)properties
              databaseQueue:(FMDatabaseQueue *)databaseQueue {
    [databaseQueue asyncInDatabase:^(FMDatabase *db) {
        NSMutableString *columns = [[NSMutableString alloc] init];
        for (NSUInteger i = 0; i < [properties count]; ++i) {
            NSString *column = [GYDCUtilities columnForClass:modelClass property:[properties objectAtIndex:i]];
            if (i) {
                [columns appendFormat:@",%@", column];
            } else {
                [columns appendString:column];
            }
        }
        NSString *sql = [[NSString alloc] initWithFormat:@"CREATE INDEX IF NOT EXISTS %@ ON %@ (%@)", [self indexNameForTable:[modelClass tableName] properties:properties], [modelClass tableName], columns];
        [db executeUpdate:sql];
    }];
}

- (BOOL)isVirtualTableForClass:(Class<GYModelObjectProtocol>)modelClass {
    if ([modelClass fts].length) {
        return YES;
    } else {
        return NO;
    }
}

- (NSString *)indexNameForTable:(NSString *)tableName properties:(NSArray *)properties {
    return [[NSString alloc] initWithFormat:@"%@_%@", tableName, [properties componentsJoinedByString:@"_"]];
}

- (BOOL)mapsIntegerForType:(GYPropertyType)type {
    switch (type) {
        case GYPropertyTypeInteger:
        case GYPropertyTypeBoolean:
            return YES;
            break;
        default:
            return NO;
            break;
    }
}

- (BOOL)mapsRealForType:(GYPropertyType)type {
    switch (type) {
        case GYPropertyTypeFloat:
        case GYPropertyTypeDate:
            return YES;
            break;
        default:
            return NO;
            break;
    }
}

- (BOOL)mapsTextForType:(GYPropertyType)type {
    switch (type) {
        case GYPropertyTypeString:
            return YES;
            break;
        default:
            return NO;
            break;
    }
}

#pragma mark - Utilities

- (GYDatabaseInfo *)databaseInfoForDbName:(NSString *)dbName {
    @synchronized(_databaseInfos) {
        GYDatabaseInfo *databaseInfo = [_databaseInfos objectForKey:dbName];
        if (!databaseInfo) {
            databaseInfo = [[GYDatabaseInfo alloc] init];
            databaseInfo.writeCount = [[self.writeCounts objectForKey:dbName] integerValue];
            databaseInfo.databaseQueue = [FMDatabaseQueue databaseQueueWithPath:[self pathForDbName:dbName]];
            [databaseInfo.databaseQueue setDatabaseQueueSpecific];
            if (kAutoTransaction) {
                [self autoTransactionForDatabaseInfo:databaseInfo];
            }
            [_databaseInfos setObject:databaseInfo forKey:dbName];
        }
        return databaseInfo;
    }
}

- (NSString *)pathForDbName:(NSString *)dbName {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];
    return [documentsDirectory stringByAppendingPathComponent:[dbName stringByAppendingPathExtension:@"db"]];
}

- (void)autoTransactionForDatabaseInfo:(GYDatabaseInfo *)databaseInfo {
    databaseInfo.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, [databaseInfo.databaseQueue queue]);
    if (databaseInfo.timer) {
        [databaseInfo.databaseQueue asyncInDatabase:^(FMDatabase *db) {
            [db beginTransaction];
        }];
        dispatch_source_set_timer(databaseInfo.timer,
                                  dispatch_time(DISPATCH_TIME_NOW, kTransactionTimeInterval * NSEC_PER_SEC),
                                  kTransactionTimeInterval * NSEC_PER_SEC,
                                  NSEC_PER_MSEC);
        dispatch_source_set_event_handler(databaseInfo.timer, ^{
            if (databaseInfo.needCommitTransaction) {
                [databaseInfo.databaseQueue syncInDatabase:^(FMDatabase *db) {
                    [db commit];
                    [db beginTransaction];
                }];
                databaseInfo.needCommitTransaction = NO;
            }
        });
        dispatch_resume(databaseInfo.timer);
    }
}

+ (NSString *)pathForAnalyzeStatistics {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];
    return [documentsDirectory stringByAppendingPathComponent:@"GYDataCenterAnalyzeStatistics"];
}

@end
