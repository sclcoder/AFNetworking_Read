//
//  Teacher.m
//  NSOperation
//
//  Created by mac on 2017/8/29.
//  Copyright © 2017年 yunjifen. All rights reserved.
//

#import "Teacher.h"

@implementation Teacher

//@synthesize height = _height;
//@synthesize age = _age;

- (instancetype)init{
    
    self = [super init];
    if (self) {
        
        // @public
        _name = @"teacher";
        
        // @protected
        _sex = @"女";

        _weight = @"100kg";
        // self->_weight = @"90kg";
        
        // @private     不能直接访问
//         _age = @"120";
        self.age = @"100"; // 间接访问私有成员变量
        
        _height = @"180cm";
        
    }
    
    return self;
}


- (NSString *)description{
    
    return [NSString stringWithFormat:@"sex:%@  name:%@  age:%@  weight:%@ height:%@",self.sex,self.name,self.age,self.weight,self.height];
    
}


@end
