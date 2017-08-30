//
//  Person.h
//  NSOperation
//
//  Created by mac on 2017/8/29.
//  Copyright © 2017年 yunjifen. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Person : NSObject

{

    /**
     （1）@public (公开的)在有对象的前提下，任何地方都可以直接访问。
     
     （2）@protected （受保护的）只能在当前类和子类的对象方法中直接访问
     
     （3）@private （私有的）只能在当前类的对象方法中才能直接访问
     
     （4）@package (框架级别的)作用域介于私有和公开之间，只要处于同一个框架中就可以直接通过变量名访问

     */
    // 默认是protect
    NSString  *_sex;
    
    @protected
    NSString  *_weight;

    @public
    NSString  *_name;
    
    @private
    NSString  *_age;
}


@property(nonatomic,copy) NSString *sex;
@property(nonatomic,copy) NSString *name;
@property(nonatomic,copy) NSString *age;
@property(nonatomic,copy) NSString *weight;

// 通过@property 自动生成的成员变量 相当于在.m文件 对外不可见
@property(nonatomic,copy) NSString *height;



@end
