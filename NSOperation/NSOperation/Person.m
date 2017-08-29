//
//  Person.m
//  NSOperation
//
//  Created by mac on 2017/8/29.
//  Copyright © 2017年 yunjifen. All rights reserved.
//

#import "Person.h"

@implementation Person


- (instancetype)init{

    self = [super init];
    if (self) {
        _sex = @"男";
        _name = @"person";
        _age = @"100";
        _height = @"180cm";
    }
    return self;
}



@end
