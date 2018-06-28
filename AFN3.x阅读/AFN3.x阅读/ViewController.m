//
//  ViewController.m
//  AFN3.x阅读
//
//  Created by 孙春磊 on 2017/8/20.
//  Copyright © 2017年 云积分. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 部分结果和AFN注解的不一样啊
    
    NSURL *baseURL = [NSURL URLWithString:@"http://example.com/v1/"];
    
    // http://example.com/v1/foo
    NSURL *url1 = [NSURL URLWithString:@"foo" relativeToURL:baseURL];
    
    // http://example.com/v1/foo?bar=baz
    NSURL *url2 = [NSURL URLWithString:@"foo?bar=baz" relativeToURL:baseURL];

    // http://example.com/foo
    NSURL *url3 = [NSURL URLWithString:@"/foo" relativeToURL:baseURL];
    
    
    // http://example.com/v1/foo
    NSURL *url4 = [NSURL URLWithString:@"foo/" relativeToURL:baseURL];
    
    // http://example.com/foo/
    NSURL *url5 = [NSURL URLWithString:@"/foo/" relativeToURL:baseURL];
    
    // http://example2.com/
    NSURL *url6 = [NSURL URLWithString:@"http://example2.com/" relativeToURL:baseURL];
    
    NSLog(@"%@",url6);
    
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
