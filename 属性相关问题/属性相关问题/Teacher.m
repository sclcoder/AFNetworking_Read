//
//  Teacher.m
//  NSOperation
//
//  Created by mac on 2017/8/29.
//  Copyright © 2017年 yunjifen. All rights reserved.
//

#import "Teacher.h"


@interface Teacher ()
@property(nonatomic,copy) NSString *hobby;

@end

@implementation Teacher

//@synthesize height = _height;
//@synthesize age = _age;


/**
 这样可以获取到父类中hobby的值
 
  使用@dynamic关键字后 编译器不会生成setter和getter 也不会生成_hobby的成员变量
 
  如果我们使用关键字 @dynamic 在类的实现文件中修饰一个属性，表明我们会为这个属性动态提供存取方法，编译器不会再默认为我们生成这个属性的 setter 和 getter 方法了，需要我们自己提供。
  当 Runtime 系统会先在 Cache 和类的方法列表(包括父类)中找要执行的方法 。
  如果没有找到Runtime 会调用 resolveInstanceMethod: 或 resolveClassMethod: 来给我们一次动态添加方法实现的机会
 */

@dynamic hobby;
// 在本例子中 可以在父类中找到setter和getter 虽然在父类中的关于hobby属性的声明是看不到 但是用runtime还是可以获取到其setter和getter 即可以间接访问


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
        
//        self->_hobby;  // 不能直接访问_hobby 因为本类中没有这个成员变量
        self.hobby;
    }
    
    return self;
}



- (NSString *)description{
    
    return [NSString stringWithFormat:@"sex:%@  name:%@  age:%@  weight:%@ height:%@ hobby:%@",self.sex,self.name,self.age,self.weight,self.height,self.hobby];
    
}


@end
