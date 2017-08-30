//
//  Teacher.h
//  NSOperation
//
//  Created by mac on 2017/8/29.
//  Copyright © 2017年 yunjifen. All rights reserved.
//

#import "Person.h"

@interface Teacher : Person

{
//    NSString *_name;  // 和父类重复了
//    NSString *_age;   // 和父类重复了
//    NSString *_sex;   // 和父类重复了
    // 父类中有个不可见的成员变量_hometown 子类中还可以声明一个
    NSString *_hometown;
    // 父类中使用@proterty标记的height属性 生成的成员变量_height 在.m中不可见 私有的
    NSString *_height;
}


@property(nonatomic,copy) NSString *hometown;


@end
