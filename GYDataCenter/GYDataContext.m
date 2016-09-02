//
//  GYDataContext.m
//  GYDataCenter
//
//  Created by 佘泽坡 on 6/29/16.
//  Copyright © 2016 佘泽坡. All rights reserved.
//

#import "GYDataContext.h"

#import "GYDCUtilities.h"
#import "GYModelObjectProtocol.h"
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

@interface GYDataContextQueue : NSObject

@property (nonatomic, strong) NSMutableDictionary *cache;

- (instancetype)initWithDBName:(NSString *)dbName;

- (void)dispatchSync:(dispatch_block_t)block;
- (void)dispatchAsync:(dispatch_block_t)block;

@end

@implementation GYDataContextQueue {
    dispatch_queue_t _queue;
}

static const void * const kDispatchQueueSpecificKey = &kDispatchQueueSpecificKey;

- (instancetype)initWithDBName:(NSString *)dbName {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create([[NSString stringWithFormat:@"GYDataCenter.%@", dbName] UTF8String], NULL);
        dispatch_queue_set_specific(_queue, kDispatchQueueSpecificKey, (__bridge void *)self, NULL);
        _cache = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dispatchSync:(dispatch_block_t)block {
    GYDataContextQueue *currentQueue = (__bridge id)dispatch_get_specific(kDispatchQueueSpecificKey);
    if (currentQueue == self) {
        block();
    } else {
        dispatch_sync(_queue, block);
    }
}

- (void)dispatchAsync:(dispatch_block_t)block {
    GYDataContextQueue *currentQueue = (__bridge id)dispatch_get_specific(kDispatchQueueSpecificKey);
    if (currentQueue == self) {
        block();
    } else {
        dispatch_async(_queue, block);
    }
}

@end

@interface GYDataContext ()<GYDBCache>
@property (nonatomic, strong) NSMutableDictionary *dataCenterQueues;
@end

@implementation GYDataContext {
    GYDBRunner *_dbRunner;
}

#pragma mark - Initialization

+ (GYDataContext *)sharedInstance {
    static GYDataContext *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GYDataContext alloc] init];
    });
    
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _dbRunner = [GYDBRunner sharedInstanceWithCacheDelegate:self];
        _dataCenterQueues = [[NSMutableDictionary alloc] init];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didReceiveMemoryWarning)
                                                     name:UIApplicationDidReceiveMemoryWarningNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(synchronizeAllData)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Interfaces

- (id)getObject:(Class<GYModelObjectProtocol>)modelClass
     properties:(NSArray *)properties
     primaryKey:(id)primaryKey {
    NSAssert([modelClass primaryKey], @"This method is for class that has a primary key.");
    if (!primaryKey) {
        NSAssert(NO, @"primaryKey cannot be nil");
        return nil;
    }
    
    GYDataContextQueue *queue = [self queueForDBName:[modelClass dbName]];
    __block id object = nil;
    [queue dispatchSync:^{
        NSMutableDictionary *cache = [self tableCacheFromDBCache:queue.cache class:modelClass];
        object = [cache objectForKey:primaryKey];
        if (!object || ((id<GYModelObjectProtocol>)object).isFault) {
            NSString *where = [self whereIdSqlForClass:modelClass];
            NSArray *objects = [_dbRunner objectsOfClass:modelClass
                                              properties:properties
                                                   where:where
                                               arguments:@[ primaryKey ]];
            object = [objects firstObject];
            if (object && !properties.count) {
                [cache setObject:object forKey:primaryKey];
            }
        }
    }];
    return object;
}

- (NSArray *)getObjects:(Class<GYModelObjectProtocol>)modelClass
             properties:(NSArray *)properties
                  where:(NSString *)where
              arguments:(NSArray *)arguments {
    GYDataContextQueue *queue = [self queueForDBName:[modelClass dbName]];
    __block NSArray *result;
    [queue dispatchSync:^{
        result = [_dbRunner objectsOfClass:modelClass
                                properties:properties
                                     where:where
                                 arguments:arguments];
        if (!properties.count) {
            NSMutableDictionary *cache = [self tableCacheFromDBCache:queue.cache class:modelClass];
            if (cache) {
                for (id<GYModelObjectProtocol> object in result) {
                    if (!object.isCacheHit) {
                        [cache setObject:object forKey:[(id)object valueForKey:[modelClass primaryKey]]];
                    }
                }
            }
        }
    }];
    return result;
}

- (NSArray *)getObjects:(Class<GYModelObjectProtocol>)leftClass
             properties:(NSArray *)leftProperties
                objects:(Class<GYModelObjectProtocol>)rightClass
             properties:(NSArray *)rightProperties
               joinType:(GYSQLJoinType)joinType
          joinCondition:(NSString *)joinCondition
                  where:(NSString *)where
              arguments:(NSArray *)arguments {
    GYDataContextQueue *queue = [self queueForDBName:[leftClass dbName]];
    __block NSArray *result;
    [queue dispatchSync:^{
        result = [_dbRunner objectsOfClass:leftClass
                                properties:leftProperties
                                     class:rightClass
                                properties:rightProperties
                                  joinType:joinType
                             joinCondition:joinCondition
                                     where:where
                                 arguments:arguments];
        if (!leftProperties.count) {
            NSMutableDictionary *cache = [self tableCacheFromDBCache:queue.cache class:leftClass];
            if (cache) {
                NSArray *objects = [result firstObject];
                for (id<GYModelObjectProtocol> object in objects) {
                    if (!object.isCacheHit) {
                        [cache setObject:object forKey:[(id)object valueForKey:[leftClass primaryKey]]];
                    }
                }
            }
        }
        if (!rightProperties.count) {
            NSMutableDictionary *cache = [self tableCacheFromDBCache:queue.cache class:rightClass];
            if (cache) {
                NSArray *objects = [result objectAtIndex:1];
                for (id<GYModelObjectProtocol> object in objects) {
                    if (!object.isCacheHit) {
                        [cache setObject:object forKey:[(id)object valueForKey:[rightClass primaryKey]]];
                    }
                }
            }
        }
    }];
    return result;
}

- (NSArray *)getIds:(Class<GYModelObjectProtocol>)modelClass
              where:(NSString *)where
          arguments:(NSArray *)arguments {
    NSAssert([modelClass primaryKey], @"This method is for class that has a primary key.");
    
    GYDataContextQueue *queue = [self queueForDBName:[modelClass dbName]];
    __block NSArray *result;
    [queue dispatchSync:^{
        result = [_dbRunner idsOfClass:modelClass
                                 where:where
                             arguments:arguments];
    }];
    return result;
}

- (NSNumber *)aggregate:(Class<GYModelObjectProtocol>)modelClass
               function:(NSString *)function
                  where:(NSString *)where
              arguments:(NSArray *)arguments {
    GYDataContextQueue *queue = [self queueForDBName:[modelClass dbName]];
    __block NSNumber *result;
    [queue dispatchSync:^{
        result = [_dbRunner aggregateOfClass:modelClass
                                    function:function
                                       where:where
                                   arguments:arguments];
    }];
    return result;
}

- (void)saveObject:(id<GYModelObjectProtocol>)object {
    if (!object) {
        NSAssert(NO, @"Object cannot be nil");
        return;
    }
    
    Class<GYModelObjectProtocol> modelClass = [object class];
    GYDataContextQueue *queue = [self queueForDBName:[modelClass dbName]];
    
    [queue dispatchSync:^{
        if (object.isSaving) {
            return;
        }
        
        [(id)object setValue:@YES forKey:@"saving"];
        [_dbRunner saveObject:object];
        NSMutableDictionary *cache = [self tableCacheFromDBCache:queue.cache class:modelClass];
        if (cache) {
            [cache setObject:object forKey:[(id)object valueForKey:[modelClass primaryKey]]];
        }
        
        [(id)object setValue:@NO forKey:@"saving"];
    }];
}

- (void)deleteObject:(Class<GYModelObjectProtocol>)modelClass
          primaryKey:(id)primaryKey {
    NSAssert([modelClass primaryKey], @"This method is for class that has a primary key.");
    if (!primaryKey) {
        NSAssert(NO, @"primaryKey cannot be nil");
        return;
    }
    
    GYDataContextQueue *queue = [self queueForDBName:[modelClass dbName]];
    
    [queue dispatchAsync:^{
        NSMutableDictionary *cache = [self tableCacheFromDBCache:queue.cache class:modelClass];
        id object = [cache objectForKey:primaryKey];
        if (object) {
            [cache removeObjectForKey:primaryKey];
            [object setValue:@YES forKey:@"deleted"];
        }
        
        NSString *where = [self whereIdSqlForClass:modelClass];
        [_dbRunner deleteClass:modelClass
                         where:where
                     arguments:@[ primaryKey ]];
    }];
}

- (void)deleteObjects:(Class<GYModelObjectProtocol>)modelClass
                where:(NSString *)where
            arguments:(NSArray *)arguments {
    GYDataContextQueue *queue = [self queueForDBName:[modelClass dbName]];
    
    [queue dispatchAsync:^{
        NSArray *ids = [_dbRunner idsOfClass:modelClass where:where arguments:arguments];
        NSMutableDictionary *cache = [self tableCacheFromDBCache:queue.cache class:modelClass];
        if (cache) {
            for (id singleId in ids) {
                id object = [cache objectForKey:singleId];
                if (object) {
                    [cache removeObjectForKey:singleId];
                    [object setValue:@YES forKey:@"deleted"];
                }
            }
        }
        
        [_dbRunner deleteClass:modelClass where:where arguments:arguments];
    }];
}

- (void)updateObject:(Class<GYModelObjectProtocol>)modelClass
                 set:(NSDictionary *)set
          primaryKey:(id)primaryKey {
    NSAssert([modelClass primaryKey], @"This method is for class that has a primary key.");
    if (!primaryKey) {
        NSAssert(NO, @"primaryKey cannot be nil");
        return;
    }
    
    GYDataContextQueue *queue = [self queueForDBName:[modelClass dbName]];
    
    [queue dispatchAsync:^{
        NSMutableDictionary *cache = [self tableCacheFromDBCache:queue.cache class:modelClass];
        [cache removeObjectForKey:primaryKey];
        
        NSString *where = [self whereIdSqlForClass:modelClass];
        [_dbRunner updateClass:modelClass set:set where:where arguments:@[ primaryKey ]];
    }];
}

- (id)updateAndReturnObject:(Class<GYModelObjectProtocol>)modelClass
                        set:(NSDictionary *)set
                 primaryKey:(id)primaryKey {
    NSAssert([modelClass primaryKey], @"This method is for class that has a primary key.");
    if (!primaryKey) {
        NSAssert(NO, @"primaryKey cannot be nil");
        return nil;
    }
    
    GYDataContextQueue *queue = [self queueForDBName:[modelClass dbName]];
    
    __block id result = nil;
    [queue dispatchSync:^{
        NSMutableDictionary *cache = [self tableCacheFromDBCache:queue.cache class:modelClass];
        result = [cache objectForKey:primaryKey];
        if (result) {
            result = [result copy];
            for (NSString *key in set) {
                id value = [set objectForKey:key];
                if (value == [NSNull null]) {
                    [result setValue:nil forKey:key];
                } else {
                    [result setValue:value forKey:key];
                }
            }
        }
        
        NSString *where = [self whereIdSqlForClass:modelClass];
        NSArray *arguments = @[ primaryKey ];
        [_dbRunner updateClass:modelClass set:set where:where arguments:arguments];
        
        if (!result) {
            result = [_dbRunner objectsOfClass:modelClass properties:nil where:where arguments:arguments].firstObject;
        }
        if (result) {
            [cache setObject:result forKey:primaryKey];
        }
    }];
    return result;
}

- (void)updateObjects:(Class<GYModelObjectProtocol>)modelClass
                  set:(NSDictionary *)set
                where:(NSString *)where
            arguments:(NSArray *)arguments {
    GYDataContextQueue *queue = [self queueForDBName:[modelClass dbName]];
    
    [queue dispatchAsync:^{
        NSString *simplifiedWhere = where;
        NSArray *simplifiedArguments = arguments;
        
        NSMutableDictionary *cache = [self tableCacheFromDBCache:queue.cache class:modelClass];
        if (cache) {
            NSArray *ids = [_dbRunner idsOfClass:modelClass where:where arguments:arguments];
            if (!ids.count) return;
            if (ids.count == 1) {
                simplifiedWhere = [self whereIdSqlForClass:modelClass];
                simplifiedArguments = ids;
            }
            
            for (id singleId in ids) {
                [cache removeObjectForKey:singleId];
            }
        }
        
        [_dbRunner updateClass:modelClass set:set where:simplifiedWhere arguments:simplifiedArguments];
    }];
}

- (void)saveRelationshipsForClass:(Class)modelClass
                            inSet:(NSDictionary *)set {
    NSDictionary *propertyTypes = [modelClass propertyTypes];
    for (NSString *property in set.allKeys) {
        GYPropertyType propertyType = [[propertyTypes objectForKey:property] unsignedIntegerValue];
        if (propertyType == GYPropertyTypeRelationship) {
            [self saveObject:[set objectForKey:property]];
        }
    }
}

- (void)inTransaction:(dispatch_block_t)block
               dbName:(NSString *)dbName {
    GYDataContextQueue *queue = [self queueForDBName:dbName];
    [queue dispatchSync:^{
        [_dbRunner beginTransactionForDbName:dbName];
        block();
        [_dbRunner commitTransactionForDbName:dbName];
    }];
}

- (void)vacuumAllDBs {
    [_dbRunner vacuumAllDBs];
}

- (void)synchronizeAllData {
    NSDictionary *dataCenterQueues;
    @synchronized(self.dataCenterQueues) {
        dataCenterQueues = [self.dataCenterQueues copy];
    }
    for (NSString *dbName in dataCenterQueues.allKeys) {
        GYDataContextQueue *queue = [dataCenterQueues objectForKey:dbName];
        [queue dispatchSync:^{
            [_dbRunner synchronizeDB:dbName];
            [queue.cache removeAllObjects];
        }];
    }
}

- (void)didReceiveMemoryWarning {
    NSArray *queues;
    @synchronized(self.dataCenterQueues) {
        queues = self.dataCenterQueues.allValues;
    }
    for (GYDataContextQueue *queue in queues) {
        [queue dispatchSync:^{
            for (NSMutableDictionary *tableCache in queue.cache.allValues) {
                if (!tableCache.count) continue;
                @autoreleasepool {
                    if ([[[[tableCache allValues] firstObject] class] cacheLevel] != GYCacheLevelDefault) continue;
                }
                
                for (id key in tableCache.allKeys) {
                    id object = [tableCache objectForKey:key];
                    if (CFGetRetainCount((__bridge CFTypeRef)object) == 2) {
                        [tableCache removeObjectForKey:key];
                    }
                }
            }
        }];
    }
}

#pragma mark - GYDBCache

- (id)objectOfClass:(Class<GYModelObjectProtocol>)modelClass id:(id)objectId {
    GYDataContextQueue *queue = [self queueForDBName:[modelClass dbName]];
    NSMutableDictionary *cache = [self tableCacheFromDBCache:queue.cache class:modelClass];
    id object = [cache objectForKey:objectId];
    [object setValue:@YES forKey:@"cacheHit"];
    return object;
}

- (void)cacheObject:(id<GYModelObjectProtocol>)modelObject {
    Class modelClass = [modelObject class];
    GYDataContextQueue *queue = [self queueForDBName:[modelClass dbName]];
    NSMutableDictionary *cache = [self tableCacheFromDBCache:queue.cache class:modelClass];
    [cache setObject:modelObject forKey:[(id)modelObject valueForKey:[modelClass primaryKey]]];
}

#pragma mark - Utilities

- (GYDataContextQueue *)queueForDBName:(NSString *)dbName {
    if (!dbName.length) {
        NSAssert(NO, @"db name cannot be nil");
        return nil;
    }
    
    @synchronized(self.dataCenterQueues) {
        GYDataContextQueue *queue = [self.dataCenterQueues objectForKey:dbName];
        if (!queue) {
            queue = [[GYDataContextQueue alloc] initWithDBName:dbName];
            [self.dataCenterQueues setObject:queue forKey:dbName];
        }
        return queue;
    }
}

- (NSMutableDictionary *)tableCacheFromDBCache:(NSMutableDictionary *)cache
                                         class:(Class<GYModelObjectProtocol>)modelClass {
    if ([modelClass cacheLevel] == GYCacheLevelNoCache)
        return nil;
    
    if (![modelClass primaryKey]) {
        return nil;
    }
    
    NSString *tableName = [modelClass tableName];
    NSMutableDictionary *tableCache = [cache objectForKey:tableName];
    if (!tableCache) {
        tableCache = [[NSMutableDictionary alloc] init];
        [cache setObject:tableCache forKey:tableName];
    }
    return tableCache;
}

- (NSString *)whereIdSqlForClass:(Class<GYModelObjectProtocol>)modelClass {
    NSAssert([modelClass primaryKey], @"modelClass must have primary key");
    
    static const void * const kWhereIdSqlKey = &kWhereIdSqlKey;
    NSString *sql = objc_getAssociatedObject(modelClass, kWhereIdSqlKey);
    
    if (!sql) {
        sql = [[NSString alloc] initWithFormat:@"WHERE %@=?", [GYDCUtilities columnForClass:modelClass property:[modelClass primaryKey]]];
        objc_setAssociatedObject(modelClass, kWhereIdSqlKey, sql, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    
    return sql;
}

@end
