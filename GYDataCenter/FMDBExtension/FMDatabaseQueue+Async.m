//
//  FMDatabaseQueue+Async.m
//  GYDataCenter
//
//  Created by 佘泽坡 on 6/25/16.
//  Copyright © 2016 佘泽坡. All rights reserved.
//

#import "FMDatabaseQueue+Async.h"
#import <sqlite3.h>

static const void * const kDatabaseQueueSpecificKey = &kDatabaseQueueSpecificKey;

@implementation FMDatabaseQueue (Async)

- (dispatch_queue_t)queue {
    return _queue;
}

- (void)setShouldCacheStatements:(BOOL)value {
    [_db setShouldCacheStatements:value];
}

- (void)setDatabaseQueueSpecific {
    dispatch_queue_set_specific(_queue, kDatabaseQueueSpecificKey, (__bridge void *)self, NULL);
}

- (void)syncInDatabase:(void (^)(FMDatabase *db))block {
    FMDatabaseQueue *currentSyncQueue = (__bridge id)dispatch_get_specific(kDatabaseQueueSpecificKey);
    
    FMDBRetain(self);
    
    dispatch_block_t task = ^() {
        
        FMDatabase *db = [self database];
        block(db);
        
        if ([db hasOpenResultSets]) {
            NSLog(@"Warning: there is at least one open result set around after performing [FMDatabaseQueue syncInDatabase:]");
            
#ifdef DEBUG
            NSSet *openSetCopy = FMDBReturnAutoreleased([[db valueForKey:@"_openResultSets"] copy]);
            for (NSValue *rsInWrappedInATastyValueMeal in openSetCopy) {
                FMResultSet *rs = (FMResultSet *)[rsInWrappedInATastyValueMeal pointerValue];
                NSLog(@"query: '%@'", [rs query]);
            }
#endif
        }
    };
    
    if (currentSyncQueue == self) {
        task();
    } else {
        dispatch_sync(_queue, task);
    }
    
    FMDBRelease(self);
}

- (void)asyncInDatabase:(void (^)(FMDatabase *db))block {
    FMDatabaseQueue *currentSyncQueue = (__bridge id)dispatch_get_specific(kDatabaseQueueSpecificKey);
    
    FMDBRetain(self);
    
    dispatch_block_t task = ^() {
        
        FMDatabase *db = [self database];
        block(db);
        
        if ([db hasOpenResultSets]) {
            NSLog(@"Warning: there is at least one open result set around after performing [FMDatabaseQueue asyncInDatabase:]");
            
#ifdef DEBUG
            NSSet *openSetCopy = FMDBReturnAutoreleased([[db valueForKey:@"_openResultSets"] copy]);
            for (NSValue *rsInWrappedInATastyValueMeal in openSetCopy) {
                FMResultSet *rs = (FMResultSet *)[rsInWrappedInATastyValueMeal pointerValue];
                NSLog(@"query: '%@'", [rs query]);
            }
#endif
        }
    };
    
    if (currentSyncQueue == self) {
        task();
    } else {
        dispatch_async(_queue, task);
    }
    
    FMDBRelease(self);
}

- (FMDatabase*)database {
    if (!_db) {
        _db = FMDBReturnRetained([FMDatabase databaseWithPath:_path]);
        
#if SQLITE_VERSION_NUMBER >= 3005000
        BOOL success = [_db openWithFlags:_openFlags];
#else
        BOOL success = [_db open];
#endif
        if (!success) {
            NSLog(@"FMDatabaseQueue could not reopen database for path %@", _path);
            FMDBRelease(_db);
            _db  = 0x00;
            return 0x00;
        }
    }
    
    return _db;
}

@end
