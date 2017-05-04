//
//  GYModelObject.h
//  GYDataCenter
//
//  Created by 佘泽坡 on 6/24/16.
//  Copyright © 2016 佘泽坡. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "GYModelObjectProtocol.h"

@interface GYModelObject : NSObject<GYModelObjectProtocol, NSCopying>

+ (instancetype)objectWithDictionary:(NSDictionary *)dictionary;

/**
 *
 * @param primaryKey Primary key value of the model object that you want to fetch.
 *
 * @return Object that match the primary key value, or nil if none is found.
 *
 */

+ (instancetype)objectForId:(id)primaryKey;

/**
 *
 * @param where Where clause of SQL. Use '?'s as placeholders for arguments.
 *
 * @param arguments Values to bind to the where clause.
 *
 * @return Objects that match the condition of the where clause.
 *
 */

+ (NSArray *)objectsWhere:(NSString *)where arguments:(NSArray *)arguments;

/**
 *
 * @param where Where clause of SQL. Use '?'s as placeholders for arguments.
 *
 * @param arguments Values to bind to the where clause.
 *
 * @return Primary key values that match the condition of the where clause.
 *
 */

+ (NSArray *)idsWhere:(NSString *)where arguments:(NSArray *)arguments;

/**
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

+ (NSNumber *)aggregate:(NSString *)function where:(NSString *)where arguments:(NSArray *)arguments;

- (void)save;
- (void)deleteObject;

/**
 *
 * @param where Where clause of SQL. Use '?'s as placeholders for arguments.
 *
 * @param arguments Values to bind to the where clause.
 *
 */

+ (void)deleteObjectsWhere:(NSString *)where arguments:(NSArray *)arguments;

/**
 *
 * @param set Property and new value pairs.
 *
 */

- (instancetype)updateObjectSet:(NSDictionary *)set;

/**
 *
 * @param set Property and new value pairs.
 *
 * @param where Where clause of SQL. Use '?'s as placeholders for arguments.
 *
 * @param arguments Values to bind to the where clause.
 *
 */

+ (void)updateObjectsSet:(NSDictionary *)set where:(NSString *)where arguments:(NSArray *)arguments;

@end
