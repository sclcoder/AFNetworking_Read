//
//  Teacher.m
//  NSOperation
//
//  Created by mac on 2017/8/29.
//  Copyright © 2017年 yunjifen. All rights reserved.
//

#import "Teacher.h"

@implementation Teacher

- (instancetype)init{
    
    self = [super init];
    if (self) {
        
        // @public
        _name = @"teacher";

        // @protected
        _sex = @"女";

        self->_weight = @"100kg";
        _weight = @"120kg";
        
        // @private     不能直接访问
        // _age = @"120";
        self.age = @"1000"; // 间接访问私有成员变量
        
        // self->height; // 不能访问
        
        NSLog(@"name:%@--age:%@--sex:%@--weight:%@",self.name,self.age,self.sex,self.weight);
        
    }
    
    return self;
}





@end
