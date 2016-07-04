//
//  GYDCUtilities.h
//  GYDataCenter
//
//  Created by Zepo She on 1/26/15.
//  Copyright (c) 2015 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "GYModelObjectProtocol.h"

@interface GYDCUtilities : NSObject

+ (GYPropertyType)propertyTypeOfClass:(Class)classType propertyName:(NSString *)propertyName;

+ (NSArray *)persistentPropertiesForClass:(Class<GYModelObjectProtocol>)modelClass;

+ (NSArray *)allColumnsForClass:(Class<GYModelObjectProtocol>)modelClass;

+ (NSString *)columnForClass:(Class<GYModelObjectProtocol>)modelClass
                    property:(NSString *)property;

+ (NSString *)propertyForClass:(Class<GYModelObjectProtocol>)modelClass
                        column:(NSString *)column;

+ (NSString *)recoverDirectory;

@end
