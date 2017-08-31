//
//  ViewController.m
//  NSURLConnction
//
//  Created by mac on 2017/8/21.
//  Copyright © 2017年 yunjifen. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>

@interface ViewController ()<NSURLConnectionDataDelegate>

@property(nonatomic,assign) long long contentLength;
@property(nonatomic,assign) long long currentLength;

@property (weak, nonatomic) IBOutlet UIProgressView *progressView;

@property(nonatomic,assign) CFRunLoopRef runloopRef;


@property(nonatomic,strong) AVAudioPlayer *player;


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    
    [self connectionDownLoad];
    
}



- (void)connectionDownLoad{

    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        
        
        NSString *urlStr = @"http://127.0.0.1/02.mp4";

//        NSString *urlStr = @"http://imgsrc.baidu.com/image/c0%3Dshijue1%2C0%2C0%2C294%2C40/sign=30161d0030292df583cea456d4583615/e1fe9925bc315c609050b3c087b1cb13485477dc.jpg";
        urlStr = [urlStr stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        
        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
        
        NSLog(@"开始");
        // 发方法会立刻进行网络请求
        // NSURLConnection *connt = [NSURLConnection connectionWithRequest:request delegate:self];
        // 如果不指定代理的工作对列 那么就在NSURLConnection的发起线程中进行代理方法回调
        // [connt setDelegateQueue:[[NSOperationQueue alloc] init]];

          NSURLConnection *connt = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];

         [connt start];
        
        NSLog(@"我来了吗");
        
        NSLog(@"connection发起线程 %@",[NSThread currentThread]);
        
        self.runloopRef = CFRunLoopGetCurrent();
        
        CFRunLoopRun();
        
    });
    
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response{

    dispatch_async(dispatch_get_main_queue(), ^{
    
        self.progressView.progress = 0;
    });
    
    self.currentLength = 0;
    self.contentLength = response.expectedContentLength;
}



- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data{

    self.currentLength += data.length;
    
    double progress = (double)self.currentLength / self.contentLength;
    
    NSLog(@"%@---progress%f",[NSThread currentThread],progress);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        self.progressView.progress = progress;
    });
    
}

-(void)connectionDidFinishLoading:(NSURLConnection *)connection{

    
    CFRunLoopStop(self.runloopRef);

}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error{
    
    CFRunLoopStop(self.runloopRef);
}


@end
