//
//  Person.m
//  NSOperation
//
//  Created by mac on 2017/8/29.
//  Copyright © 2017年 yunjifen. All rights reserved.
//

#import "Person.h"

@interface Person ()

@property(nonatomic,copy) NSString *hometown;

@end


@implementation Person

{
    // 私有的而且对外部不可见
    NSString *_hometown;
}

- (instancetype)init{

    self = [super init];
    if (self) {
        _sex = @"男";
        _name = @"person";
        _age = @"1000";
        _weight = @"2000kg";
        _height = @"1800cm";
    }
    return self;
}


- (NSString *)description{
    
    return [NSString stringWithFormat:@"sex:%@  name:%@  age:%@  weight:%@ height:%@",self.sex,self.name,self.age,self.weight,self.height];
    
}


@end
