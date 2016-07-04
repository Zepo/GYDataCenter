//
//  GYReflection.h
//  GYDBRunner
//
//  Created by Zepo She on 12/29/14.
//  Copyright (c) 2014 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GYReflection : NSObject

+ (NSString *)propertyTypeOfClass:(Class)classType propertyName:(NSString *)propertyName;

@end
