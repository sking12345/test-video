//
//  ViewController.m
//  testking
//
//  Created by king on 2019/3/25.
//  Copyright © 2019 ds. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import<AudioToolbox/AudioToolbox.h>
#include "lib/thread_pool.h"
#include "lib/socket.h"

@interface ViewController ()  <AVCaptureVideoDataOutputSampleBufferDelegate>
@property(nonatomic, strong) AVCaptureSession *captureSession;
@property (weak, nonatomic) IBOutlet UIImageView *recording_view;
@property (weak, nonatomic) IBOutlet UIImageView *play_view;
@property (weak, nonatomic) IBOutlet UIButton *option_btn;
@property (weak, nonatomic) IBOutlet UITextView *log_view;
@property (weak, nonatomic) IBOutlet UITextField *IP;
@property (weak, nonatomic) IBOutlet UITextField *Port;
@end

@implementation ViewController
struct thread_pool * pool = NULL;
struct client_base * cbase = NULL;
int  option_btn = 0;
- (void)viewDidLoad {
   
    [super viewDidLoad];
    [self init_style];
    // Do any additional setup after loading the view, typically from a nib.
}

/**关闭键盘 */
-(void)close_keyboard
{
    [self write_logs:@"close_keyboard"];
    NSLog(@"close_keyboard");
   [self.view endEditing:YES]; //关闭键盘
}

/** 初始化样式*/
-(void)init_style
{
    self.recording_view.layer.borderWidth = 2;
    self.play_view.layer.borderWidth = 2;
    self.log_view.layer.borderWidth = 2;
    
    self.recording_view.layer.borderColor =  [[UIColor redColor]CGColor];
    self.play_view.layer.borderColor =  [[UIColor redColor]CGColor];
    self.log_view.layer.borderColor =  [[UIColor redColor]CGColor];
    
    self.log_view.editable = NO;
    self.Port.keyboardType = UIKeyboardTypePhonePad;
    [self write_logs:@"init_style"];
    /** 跟view 添加一个点击事件,用于关闭键盘操作*/
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(close_keyboard)];
    [self.view addGestureRecognizer:tapGesture];

}

-(void)write_logs:(NSString*)text
{
    NSString *txt = self.log_view.text;
    if([txt isEqualToString:@""])
    {
        NSString *str =  [[NSString alloc] initWithFormat:@"%@",text];
        [self.log_view setText:str];
    }else{
        NSString *str =  [[NSString alloc] initWithFormat:@"%@\r\n%@",self.log_view.text,text];
        [self.log_view setText:str];
    }
    [self.log_view scrollRangeToVisible:NSMakeRange(self.log_view.text.length, 1)];
}


-(IBAction)clear_logs:(id)sender
{
    [self.log_view setText:@""];
}

-(IBAction)start_click:(id)sender{
    if(option_btn == 0)
    {
        option_btn = 1;
        [self write_logs:@"start"];
        [self.option_btn setTitle:@"stop" forState:UIControlStateNormal];
    }else{
        option_btn = 0;
         [self write_logs:@"stop"];
         [self.option_btn setTitle:@"start" forState:UIControlStateNormal];
    }
//    pool = thread_pool_init(1, 10);
//    cbase = tcp_client_init("192.168.83.62", 8888);
//    int fd = tcp_client_start(cbase, pool, NULL, NULL);
//    printf("fd:%d\n",fd);
}

@end
