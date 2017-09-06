//
//  Person.m
//  NSOperation
//
//  Created by mac on 2017/8/29.
//  Copyright © 2017年 yunjifen. All rights reserved.
//

#import "Person.h"

// 写在.m中类扩展的 子类也无法看到
// 但是子类可以通过runtime动态获取到属性的setter和getter  即使这些属性是在 .m类扩展中
@interface Person ()

@property(nonatomic,copy) NSString *hometown;

@property(nonatomic,copy) NSString *hobby;

@property(nonatomic,copy,readwrite) NSString *wife;


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
        
        _hobby = @"person-sport";
    }
    return self;
}


- (void)setWife:(NSString *)wife{

    _wife = [wife copy];
    
}





- (NSString *)description{
    
    return [NSString stringWithFormat:@"sex:%@  name:%@  age:%@  weight:%@ height:%@  hobby:%@",self.sex,self.name,self.age,self.weight,self.height,self.hobby];
    
}


@end
