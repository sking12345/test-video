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
    [self setcupSession];
    [self setupInput];
    [self setupOutput];

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

-(void)start
{

    [_captureSession startRunning];
}
-(void)stop
{
     [_captureSession stopRunning];
}

-(IBAction)start_click:(id)sender{
    if(option_btn == 0)
    {
        option_btn = 1;
        [self write_logs:@"start"];
        [self.option_btn setTitle:@"stop" forState:UIControlStateNormal];
        [self start];
    }else{
        option_btn = 0;
         [self write_logs:@"stop"];
         [self.option_btn setTitle:@"start" forState:UIControlStateNormal];
         [self stop];
    }
//    pool = thread_pool_init(1, 10);
//    cbase = tcp_client_init("192.168.83.62", 8888);
//    int fd = tcp_client_start(cbase, pool, NULL, NULL);
//    printf("fd:%d\n",fd);
}



-(void)setcupSession{
    AVCaptureSession *captureSession = [[AVCaptureSession alloc] init];
    _captureSession = captureSession;
    captureSession.sessionPreset = AVCaptureSessionPreset352x288;
    
}

//会话添加输入对象
- (void)setupInput {
    AVCaptureDevice *videoDevice = [self deviceWithPosition:AVCaptureDevicePositionFront];
    AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
    if([_captureSession canAddInput:videoInput]) {
        [_captureSession addInput:videoInput];
    }
}
//会话添加输出对象
- (void)setupOutput {
    AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    videoOutput.minFrameDuration = CMTimeMake(1,25);
    videoOutput.videoSettings = @{(NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)};
    dispatch_queue_t queue = dispatch_queue_create("queue", DISPATCH_QUEUE_SERIAL);
    [videoOutput setSampleBufferDelegate:self queue:queue];
    if([_captureSession canAddOutput:videoOutput]) {
        [_captureSession addOutput:videoOutput];
    }
    AVCaptureConnection *connection = [videoOutput connectionWithMediaType:AVMediaTypeVideo];
    connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    connection.videoMirrored = YES;
}


- (AVCaptureDevice *)deviceWithPosition:(AVCaptureDevicePosition)position {
    NSArray *devices = [AVCaptureDevice devices];
    for (AVCaptureDevice *device in devices) {
        if(device.position == AVCaptureDevicePositionFront) {
            return device;
        }
    }
    return nil;
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CIImage *ciImage = [CIImage imageWithCVImageBuffer:imageBuffer];
    UIImage *image = [UIImage imageWithCIImage:ciImage];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.recording_view.image = image;
        
    });
    /*
    dispatch_async(dispatch_get_main_queue(), ^{
        CVPixelBufferLockBaseAddress(imageBuffer, 0);
        size_t pixelWidth = CVPixelBufferGetWidth(imageBuffer);
        size_t pixelHeight = CVPixelBufferGetHeight(imageBuffer);
        size_t y_size = pixelWidth * pixelHeight;
        size_t uv_size = y_size / 2;
        unsigned char *yuv_frame = (uint8_t*)malloc(uv_size + y_size);
        void *imageAddress = CVPixelBufferGetBaseAddressOfPlane(imageBuffer,0); //yyyyy
        size_t row0=CVPixelBufferGetBytesPerRowOfPlane(imageBuffer,0);
        void *imageAddress1=CVPixelBufferGetBaseAddressOfPlane(imageBuffer,1);//UVUVUVUV
        size_t row1=CVPixelBufferGetBytesPerRowOfPlane(imageBuffer,1);
        for (int i=0; i<pixelHeight; ++i) {
            memcpy(yuv_frame+i*pixelWidth, imageAddress+i*row0, pixelWidth);
        }
        uint8_t *UV=imageAddress1;
        uint8_t *U=yuv_frame+y_size;
        uint8_t *V=U+y_size/4;
        for (int i=0; i<0.5*pixelHeight; i++)
        {
            for (int j=0; j<0.5*pixelWidth; j++)
            {
                *(U++)=UV[j<<1];
                *(V++)=UV[(j<<1)+1];
            }
            UV+=row1;
        }
        if(cbase!=NULL)
        {
            
            //thread_add_job(cbase->thread_pool, wirte_tcp,yuv_frame,(int)(uv_size + y_size), -1);
        }
        free(yuv_frame);
        yuv_frame = NULL;
        CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    });
     */
}

@end
