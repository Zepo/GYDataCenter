//
//  GYDataContext.h
//  GYDataCenter
//
//  Created by 佘泽坡 on 6/29/16.
//  Copyright © 2016 佘泽坡. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "GYDBRunner.h"

@protocol GYModelObjectProtocol;

@interface GYDataContext : NSObject

+ (GYDataContext *)sharedInstance;

/**
 *
 * @param modelClass Class of the model object that you want to fetch.
 *
 * @param properties Properties you need. Pass nil to get values of all properties.
 *
 * @param primaryKey Primary key value of the model object that you want to fetch.
 *
 * @return Object that match the primary key value, or nil if none is found.
 *
 */

- (id)getObject:(Class<GYModelObjectProtocol>)modelClass
     properties:(NSArray *)properties
     primaryKey:(id)primaryKey;

/**
 *
 * @param modelClass Class of the model objects that you want to fetch.
 *
 * @param properties Properties you need. Pass nil to get values of all properties.
 *
 * @param where Where clause of SQL. Use '?'s as placeholders for arguments.
 *
 * @param arguments Values to bind to the where clause.
 *
 * @return Objects that match the condition of the where clause.
 *
 */

- (NSArray *)getObjects:(Class<GYModelObjectProtocol>)modelClass
             properties:(NSArray *)properties
                  where:(NSString *)where
              arguments:(NSArray *)arguments;

/** Join two tables.
 *
 * @param leftClass Class of the first join table.
 *
 * @param leftProperties Properties of leftClass that you need. Pass nil to get values of all properties.
 *
 * @param rightClass Class of the second join table.
 *
 * @param rightProperties Properties of rightClass that you need. Pass nil to get values of all properties.
 *
 * @param joinType GYSQLJoinTypeInner, GYSQLJoinTypeLeft or GYSQLJoinTypeCross.
 *
 * @param joinCondition Join condition. For example: 'leftTableName.property1 = rightTableName.property2'.
 *
 * @param where Where clause of SQL. Use '?'s as placeholders for arguments.
 *
 * @param arguments Values to bind to the where clause.
 *
 * @return @[ @[`Objects of left class`], @[`objects of right class`] ].
 *
 */

- (NSArray *)getObjects:(Class<GYModelObjectProtocol>)leftClass
             properties:(NSArray *)leftProperties
                objects:(Class<GYModelObjectProtocol>)rightClass
             properties:(NSArray *)rightProperties
               joinType:(GYSQLJoinType)joinType
          joinCondition:(NSString *)joinCondition
                  where:(NSString *)where
              arguments:(NSArray *)arguments;

/**
 *
 * @param modelClass Class of the model objects that you want to query.
 *
 * @param where Where clause of SQL. Use '?'s as placeholders for arguments.
 *
 * @param arguments Values to bind to the where clause.
 *
 * @return Primary key values that match the condition of the where clause.
 *
 */

- (NSArray *)getIds:(Class<GYModelObjectProtocol>)modelClass
              where:(NSString *)where
          arguments:(NSArray *)arguments;

/**
 *
 * @param modelClass Class of the model objects that you want to query.
 *
 * @param function Aggregate function. For example: 'count(*)', 'sum(value)'...
 *
 * @param where Where clause of SQL. Use '?'s as placeholders for arguments.
 *
 * @param arguments Values to bind to the where clause.
 *
 * @return Result of the aggregate function.
 *
 */

- (NSNumber *)aggregate:(Class<GYModelObjectProtocol>)modelClass
               function:(NSString *)function
                  where:(NSString *)where
              arguments:(NSArray *)arguments;

/**
 *
 * @param object The object to be saved.
 *
 */

- (void)saveObject:(id<GYModelObjectProtocol>)object;

- (void)deleteObject:(Class<GYModelObjectProtocol>)modelClass
          primaryKey:(id)primartyKey;

/**
 *
 * @param modelClass Class of the model objects that you want to delete.
 *
 * @param where Where clause of SQL. Use '?'s as placeholders for arguments.
 *
 * @param arguments Values to bind to the where clause.
 *
 */

- (void)deleteObjects:(Class<GYModelObjectProtocol>)modelClass
                where:(NSString *)where
            arguments:(NSArray *)arguments;

/**
 *
 * @param modelClass Class of the model object that you want to update.
 *
 * @param set Property and new value pairs.
 *
 * @param primaryKey Primary key value of the model object that you want to update.
 *
 */

- (void)updateObject:(Class<GYModelObjectProtocol>)modelClass
                 set:(NSDictionary *)set
          primaryKey:(id)primaryKey;

/**
 *
 * @param modelClass Class of the model object that you want to update.
 *
 * @param set Property and new value pairs.
 *
 * @param primaryKey Primary key value of the model object that you want to update.
 *
 * @return A new updated object.
 *
 */

- (id)updateAndReturnObject:(Class<GYModelObjectProtocol>)modelClass
                        set:(NSDictionary *)set
                 primaryKey:(id)primaryKey;

/**
 *
 * @param modelClass Class of the model objects that you want to update.
 *
 * @param set Property and new value pairs.
 *
 * @param where Where clause of SQL. Use '?'s as placeholders for arguments.
 *
 * @param arguments Values to bind to the where clause.
 *
 */

- (void)updateObjects:(Class<GYModelObjectProtocol>)modelClass
                  set:(NSDictionary *)set
                where:(NSString *)where
            arguments:(NSArray *)arguments;

- (void)inTransaction:(dispatch_block_t)block
               dbName:(NSString *)dbName;

- (void)vacuumAllDBs;

- (void)synchronizeAllData;

@end
