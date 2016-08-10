//
//  FMDatabaseQueue+Async.h
//  GYDataCenter
//
//  Created by 佘泽坡 on 6/25/16.
//  Copyright © 2016 佘泽坡. All rights reserved.
//

#import <FMDB/FMDB.h>

@interface FMDatabaseQueue (Async)

- (dispatch_queue_t)queue;

- (void)setShouldCacheStatements:(BOOL)value;

- (void)setDatabaseQueueSpecific;

- (void)syncInDatabase:(void (^)(FMDatabase *db))block;
- (void)asyncInDatabase:(void (^)(FMDatabase *db))block;

@end
