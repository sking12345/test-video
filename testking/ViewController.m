//
//  ViewController.m
//  testking
//
//  Created by king on 2019/3/25.
//  Copyright © 2019 ds. All rights reserved.
//
/**
 * 注意事项:本demo 的视频采集后的yuv420 数据的yuv 排列方式为 yyyyuuvv,查询得知 iOS UIIamge 只支持的是nv12的(YYYYUVUV)的这种数据格式,
 * 所以在将h264的数据转换为yuv420 后，应进行yuv 的排列修正为iOS 支持的nv12 方式
 */
#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <AudioToolbox/AudioToolbox.h>
#import <MediaToolbox/MediaToolbox.h>
#include "thread_pool.h"
#include "include/socket.h"
#include "include/x264.h"
#include "include/log.h"
#include "fdk-aac/aacenc_lib.h"

#include "libavcodec/avcodec.h"
#include "libavformat/avformat.h"

#include "libavutil/mathematics.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
@interface ViewController ()  <AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureAudioDataOutputSampleBufferDelegate>
@property(nonatomic, strong) AVCaptureSession *captureSession;
@property (weak, nonatomic) IBOutlet UIImageView *recording_view;
@property (weak, nonatomic) IBOutlet UIImageView *play_view;
@property (weak, nonatomic) IBOutlet UIButton *option_btn;
@property (weak, nonatomic) IBOutlet UIButton *type_btn;
@property (weak, nonatomic) IBOutlet UITextView *log_view;
@property (weak, nonatomic) IBOutlet UITextField *IP;
@property (weak, nonatomic) IBOutlet UITextField *Port;
@property (nonatomic, strong) AVCaptureConnection    *videoConnection;
@property (nonatomic, strong) AVCaptureConnection    *audioConnection;

@property (nonatomic, strong) dispatch_queue_t           videoQueue;
@property (nonatomic, strong) dispatch_queue_t           AudioQueue;
@end

@class QGAudioRecord;
@protocol QGAudioRecordDelegate <NSObject>

- (void)audioRecord:(QGAudioRecord*)AudioRecord recordCallBack:(AudioBufferList*)bufferList;
- (void)audioPlayer:(QGAudioRecord*)AudioRecord playCallBack:(AudioBufferList*)bufferList inNumberFrames:(UInt32)inNumberFrames;

@end
@interface QGAudioRecord : NSObject

@property (nonatomic, weak) id<QGAudioRecordDelegate> delegate;

+ (instancetype)shareManager;

@end

@implementation ViewController
struct thread_pool * pool = NULL;
struct client_base * cbase = NULL;

AudioComponentInstance    audioUnit;    //音频uint
 AudioStreamBasicDescription streamFormat;
static ViewController *_self = nil;

int  option_btn = 0;
#define IMAGE_WIDTH   288
#define IMAGE_HEIGHT  352

#define PROFILE_AAC_LC 2
#define PROFILE_AAC_HE 5
#define PROFILE_AAC_HE_v2 29
#define PROFILE_AAC_LD 23
#define PROFILE_AAC_ELD 39

#define kRate 16000 //采样率
#define kChannels   (1)//声道数
#define kBits       (16)//位数



#define CLEAR(x) (memset((&x),0,sizeof(x)))
#define ENCODER_PRESET "veryfast"    //启用各种保护质量的算法

#define ENCODER_TUNE   "zerolatency"    //不用缓存,立即返回编码数据
#define ENCODER_PROFILE  "baseline"        //avc 规格,从低到高分别为：Baseline、Main、High。
#define ENCODER_COLORSPACE X264_CSP_I420

AudioConverterRef converter; //音频

typedef struct my_x264_encoder {
    x264_param_t  *x264_parameter;    //x264参数结构体
    x264_t  *x264_encoder;            //控制一帧一帧的编码
    x264_picture_t *yuv420p_picture; //描述视频的特征
    long colorspace;
    x264_nal_t *nal;
    int n_nal;
    char parameter_preset[20];
    char parameter_tune[20];
    char parameter_profile[20];
} my_x264_encoder;

my_x264_encoder *encoder = nil;

AVCodec *pCodec = NULL;
AVCodecContext *pCodecCtx = NULL;

AVCodecParserContext *pCodecParserCtx = NULL;
AVPacket packet = {0};
struct SwsContext *img_convert_ctx = NULL;

int type_btn_num = 0;

-(IBAction)type_btn_click:(id)sender{
   
    if(type_btn_num == 0)   //视频
    {
        [self.type_btn setTitle:@"视频" forState:UIControlStateNormal];
    }else if(type_btn_num == 1) //音频
    {
         [self.type_btn setTitle:@"音频" forState:UIControlStateNormal];
    }else{  //音视频
         [self.type_btn setTitle:@"音视频" forState:UIControlStateNormal];
    }
    type_btn_num++;
    type_btn_num = type_btn_num%3;
}

- (void)viewDidLoad {
   
    [super viewDidLoad];
    [self init_style];
    init_x264();
    init_ffmpeg();
    init_fdk_acc();
    init_decode_audio();
    _self = self;
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
    [self setupAudioInput];
    [self setupInput];
    [self setupOutput];
    [self init_uint];
   
}

HANDLE_AACENCODER audio_encoder;

//初始化fdk-acc
int init_fdk_acc()
{
    AACENC_ERROR rt = aacEncOpen(&audio_encoder, 0,0);
    if (rt != AACENC_OK) {
        NSLog(@"aac enc open error %zd",rt);
        return -1;
    }
    if (aacEncoder_SetParam(audio_encoder, AACENC_AOT, 2) != AACENC_OK) { 
        printf("Unable to set the AOT\n");
        return -1;
    }
    
    if (aacEncoder_SetParam(audio_encoder, AACENC_SAMPLERATE, kRate) != AACENC_OK) {
        printf("Unable to set the AOT\n");
        return -1;
    }
    if (aacEncoder_SetParam(audio_encoder, AACENC_CHANNELMODE, 1) != AACENC_OK) {  //2 channle
        printf("Unable to set the channel mode\n");
        return -1;
    }
    if (aacEncoder_SetParam(audio_encoder, AACENC_BITRATE, 64 * 1000) != AACENC_OK) {
        printf("Unable to set the bitrate\n");
        return -1;
    }
    if (aacEncoder_SetParam(audio_encoder, AACENC_TRANSMUX, 2) != AACENC_OK) { //0-raw 2-adts
        printf("Unable to set the ADTS transmux\n");
        return -1;
    }
    
    if (aacEncEncode(audio_encoder, NULL, NULL, NULL, NULL) != AACENC_OK) {
        printf("Unable to initialize the encoder\n");
        return -1;
    }
    
    AACENC_InfoStruct info = { 0 };
    if (aacEncInfo(audio_encoder, &info) != AACENC_OK) {
        printf("Unable to get the encoder info\n");
        return -1;
    }
    return 1;
}

//初始化x264
void init_x264()
{
    encoder = (my_x264_encoder*)malloc(sizeof(my_x264_encoder));
    if(encoder == NULL)
    {
        printf("%s\n", "can't malloc my_x264_encoder");
        exit(EXIT_FAILURE);
    }
    CLEAR(*encoder);
    encoder->n_nal = 0;
    strcpy(encoder->parameter_preset,ENCODER_PRESET);
    strcpy(encoder->parameter_tune,ENCODER_TUNE);
    encoder->x264_parameter = (x264_param_t*)malloc(sizeof(x264_param_t));
    if(encoder->x264_parameter == NULL)
    {
        printf("malloc x264_parameter error!\n");
        exit(EXIT_FAILURE);
    }
    CLEAR(*(encoder->x264_parameter));
    x264_param_default(encoder->x264_parameter);    //自动检测系统配置默认参数
    //设置速度和质量要求
    int ret = x264_param_default_preset(encoder->x264_parameter,encoder->parameter_preset,encoder->parameter_tune);
    if( ret < 0 )
    {
        printf("%s\n", "x264_param_default_preset error");
        exit(EXIT_FAILURE);
    }
    //修改x264的配置参数
    encoder->x264_parameter->i_threads = X264_SYNC_LOOKAHEAD_AUTO;    //cpuFlags 去空缓存继续使用不死锁保证
    encoder->x264_parameter->i_width   = IMAGE_WIDTH;        //宽
    encoder->x264_parameter->i_height  = IMAGE_HEIGHT;        //高
    encoder->x264_parameter->i_frame_total = 0;    //要编码的总帧数,不知道的用0
    encoder->x264_parameter->i_keyint_max  = 25; //设定IDR帧之间的最大间隔
    encoder->x264_parameter->i_bframe        = 5;        //两个参考帧之间的B帧数目,该代码可以不设定
    encoder->x264_parameter->b_open_gop       = 0;        //GOP是指帧间的预测都是在GOP中进行的
    encoder->x264_parameter->i_bframe_pyramid  = 0; //是否允许部分B帧作为参考帧
    encoder->x264_parameter->i_bframe_adaptive = X264_B_ADAPT_TRELLIS; //自适应B帧判定
//    encoder->x264_parameter->i_log_level       = X264_LOG_DEBUG;    //日志输出
    
    encoder->x264_parameter->i_fps_den         = 1;//码率分母
    encoder->x264_parameter->i_fps_num         = 25;//码率分子
    encoder->x264_parameter->b_intra_refresh   = 1;    //是否使用周期帧内涮新替换新的IDR帧
    encoder->x264_parameter->b_annexb          = 1;    //如果是ture，则nalu 之前的4个字节前缀是0x000001,
    //如果是false,则为大小
    strcpy(encoder->parameter_profile,ENCODER_PROFILE);
    ret = x264_param_apply_profile(encoder->x264_parameter,encoder->parameter_profile); //设置avc 规格
    if( ret < 0 )
    {
        printf("%s\n", "x264_param_apply_profile error");
        exit(EXIT_FAILURE);
    }
    
    encoder->x264_encoder = x264_encoder_open(encoder->x264_parameter);
    encoder->colorspace = ENCODER_COLORSPACE;    //设置颜色空间,yuv420的颜色空间
    encoder->yuv420p_picture = (x264_picture_t *)malloc(sizeof(x264_picture_t ));
    if(encoder->yuv420p_picture == NULL)
    {
        printf("%s\n", "encoder->yuv420p_picture malloc error");
        exit(EXIT_FAILURE);
    }
    //按照颜色空间分配内存,返回内存首地址
    ret = x264_picture_alloc(encoder->yuv420p_picture,encoder->colorspace,IMAGE_WIDTH,IMAGE_HEIGHT);
    if( ret<0 )
    {
        printf("%s\n", "x264_picture_alloc malloc error");
        exit(EXIT_FAILURE);
    }
    encoder->yuv420p_picture->img.i_csp = encoder->colorspace;    //配置颜色空间
    encoder->yuv420p_picture->img.i_plane = 3;                    //配置图像平面个数
    encoder->yuv420p_picture->i_type = X264_TYPE_AUTO;            //帧的类型,编码过程中自动控制
    av_init_packet(&packet);
}
// AVFrame *pFrame = NULL;
void init_ffmpeg()
{
    av_register_all();
    pCodec = avcodec_find_decoder(AV_CODEC_ID_H264);
    pCodecCtx = avcodec_alloc_context3(pCodec);
    pCodecParserCtx = av_parser_init(AV_CODEC_ID_H264);
    if (!pCodecParserCtx){
        printf("Could not allocate video parser context\n");
        return;
    }
    if (pCodec->capabilities&AV_CODEC_CAP_TRUNCATED)
    {
          pCodecCtx->flags |= AV_CODEC_FLAG_TRUNCATED;
    }
    pCodecCtx->codec_type =  AVMEDIA_TYPE_VIDEO;
    pCodecCtx->bit_rate = 0;
    pCodecCtx->time_base.den = 25;
    pCodecCtx->width = IMAGE_WIDTH;//视频宽
    pCodecCtx->height = IMAGE_HEIGHT;//视频高
    if (avcodec_open2(pCodecCtx, pCodec, NULL) < 0) {
        printf("Could not open codec\n");
        return ;
    }else{
        printf("init frame sucess\n");
    }
    
}

uint8_t *videoData = NULL;
int videoData_size = 0;

int tcp_send_status = 0x00;

void ffmpeg(int data_size,uint8_t *data)
{
    
    if(data_size<=27)
    {
        if(videoData == NULL)
        {
            videoData = (uint8_t*)malloc(data_size);
            memset(videoData, 0x00, data_size);
        }
        int _start = videoData_size;
        videoData_size += data_size;
        videoData = (uint8_t*)realloc(videoData,videoData_size);
        memcpy(videoData+_start,data,data_size);
        return;
    }else{
        int _start = videoData_size;
        videoData_size += data_size;
        videoData = (uint8_t*)realloc(videoData,videoData_size);
        memcpy(videoData+_start,data,data_size);
    }
    AVPacket packet = {0};
    av_new_packet(&packet, videoData_size);
     memcpy(packet.data, videoData, videoData_size);
    int frameFinished = data_size;//这个是随便填入数字，没什么作用
    AVFrame *pFrame = av_frame_alloc();
    int got_picture = 0;
    int ret = avcodec_decode_video2(pCodecCtx, pFrame, &got_picture, &packet);
    if(ret>0)
    {
        if(got_picture)
        {

            int decodedBufferSize = avpicture_get_size(AV_PIX_FMT_YUV420P,IMAGE_WIDTH,IMAGE_HEIGHT);
            uint8_t * decodedBuffer = (uint8_t *)malloc(decodedBufferSize);
            memset(decodedBuffer,0x00,decodedBufferSize);
            avpicture_layout((AVPicture*)pFrame,AV_PIX_FMT_YUVJ420P,IMAGE_WIDTH,IMAGE_HEIGHT,decodedBuffer,decodedBufferSize);
             if(tcp_send_status == 0x01)
             {
                 //tcp_send(cbase->sfd,decodedBuffer,decodedBufferSize);
             }
            NSDictionary *pixelAttributes = @{(NSString*)kCVPixelBufferIOSurfacePropertiesKey:@{}};
            CVPixelBufferRef pixelBuffer = NULL;
            CVReturn result = CVPixelBufferCreate(kCFAllocatorDefault,
                                                  IMAGE_WIDTH,
                                                  IMAGE_HEIGHT,
                                                  kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                                  (__bridge CFDictionaryRef)(pixelAttributes),
                                                  &pixelBuffer);
            if (result != kCVReturnSuccess) {
                NSLog(@"Unable to create cvpixelbuffer %d", result);
            }
            CVPixelBufferLockBaseAddress(pixelBuffer,0);    //锁住
            unsigned char *yDestPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
            unsigned char *uvDestPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
            memcpy(yDestPlane, decodedBuffer, IMAGE_WIDTH * IMAGE_HEIGHT);  //y数据
            uint8_t * src_U = decodedBuffer+ IMAGE_WIDTH * IMAGE_HEIGHT;
            uint8_t * src_V = src_U+ IMAGE_WIDTH * IMAGE_HEIGHT/4;
            uint8_t *dest_U = uvDestPlane;
            /**数据重新排列，采集到yuv420的排序为yyyyuuvv,转换为iOS 支持的yyyyuvuv */
            for( int i = 0 ; i < IMAGE_WIDTH * IMAGE_HEIGHT / 4 ; i++ ){
                *(dest_U++) = *(src_U++);
                *(dest_U++) = *(src_V++);
            }
            CIImage *coreImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
            UIImage *image = [UIImage imageWithCIImage:coreImage];
            CVPixelBufferRelease(pixelBuffer);
             _self.play_view.image = image;
            free(decodedBuffer);
            decodedBuffer=NULL;
        }else{
            printf("no ok1...\n");
        }
    }else{
        printf("no ok...\n");
    }
    av_frame_free(&pFrame);
    free(videoData);
     videoData=NULL;
    videoData_size = 0;
   
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

-(void)start_tcp
{
    if(pool == NULL)
    {
        pool = thread_pool_init(1, 10);
    }
    if(cbase==NULL)
    {
        NSString *_ip = self.IP.text;
        NSString *_port =self.Port.text;
        cbase= tcp_client_init([_ip UTF8String], [_port intValue]);
        tcp_client_start(cbase, pool, NULL, NULL);
    }
}

-(void)stop_tcp
{
    if(pool != NULL)
    {
        thread_pool_destroy(&pool);
    }
    if(cbase!=NULL)
    {
        tcp_client_end(&cbase);
    }
}

-(void)start
{
    [self start_uinit];
    if(tcp_send_status == 0x00)
    {
         [_captureSession startRunning];
    }else  if(cbase!=NULL)
    {
        [_captureSession startRunning];
    }
}
-(void)stop
{
    [_captureSession stopRunning];
    [self stop_uinit];
}

-(IBAction)start_click:(id)sender{
    if(option_btn == 0)
    {
        option_btn = 1;
        [self write_logs:@"start"];
        [self.option_btn setTitle:@"stop" forState:UIControlStateNormal];
        [self start_tcp];
        [self start];
    }else{
        option_btn = 0;
         [self write_logs:@"stop"];
         [self.option_btn setTitle:@"start" forState:UIControlStateNormal];
         [self stop];
    }
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

/**输出*/
OSStatus recordCallback_xb(void *inRefCon,
                           AudioUnitRenderActionFlags *ioActionFlags,
                           const AudioTimeStamp *inTimeStamp,
                           UInt32 inBusNumber,
                           UInt32 inNumberFrames,
                           AudioBufferList *ioData){
    
    
    QGAudioRecord *audioRecord = (__bridge QGAudioRecord*)inRefCon;
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mData = NULL;
    bufferList.mBuffers[0].mDataByteSize = 0;
    
    AudioUnitRender(audioUnit,
                    ioActionFlags,
                    inTimeStamp,
                    1,
                    inNumberFrames,
                    &bufferList);
    //    AudioBuffer buffer = bufferList.mBuffers[0];
    printf("bufferList.mBuffers[0].mDataByteSize....:%d\n", bufferList.mBuffers[0].mDataByteSize);
//    tcp_send(cbase->sfd, bufferList.mBuffers[0].mData,  bufferList.mBuffers[0].mDataByteSize); //pcm数据正常
    
    encode_audio(bufferList.mBuffers[0].mData, bufferList.mBuffers[0].mDataByteSize);
    return noErr;
}

OSStatus playCallback_xb(
                         void *inRefCon,
                         AudioUnitRenderActionFlags     *ioActionFlags,
                         const AudioTimeStamp         *inTimeStamp,
                         UInt32                         inBusNumber,
                         UInt32                         inNumberFrames,
                         AudioBufferList             *ioData)

{
    
     memset(ioData->mBuffers[0].mData, 0, ioData->mBuffers[0].mDataByteSize);
    return 0;
}


-(void) start_uinit
{
    AudioOutputUnitStart(audioUnit);
}

-(void) stop_uinit
{
    AudioOutputUnitStop(audioUnit);
}

-(void) init_uint
{
    //设置session
    NSError *error = nil;
    AVAudioSession* session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error:&error];
    [session setActive:YES error:nil];
    //初始化audioUnit
    AudioComponentDescription outputDesc;
    outputDesc.componentType = kAudioUnitType_Output;
    outputDesc.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    outputDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    outputDesc.componentFlags = 0;
    outputDesc.componentFlagsMask = 0;
    AudioComponent outputComponent = AudioComponentFindNext(NULL, &outputDesc);

    AudioComponentInstanceNew(outputComponent, &audioUnit);
    
    
//    audioUnit
    
    //启用录音功能
    UInt32 inputEnableFlag = 1;
    CheckError(AudioUnitSetProperty(audioUnit,
                                    kAudioOutputUnitProperty_EnableIO,
                                    kAudioUnitScope_Input,
                                    1,
                                    &inputEnableFlag,
                                    sizeof(inputEnableFlag)),
               "Open input of bus 1 failed");
    //    Open output of bus 0(output speaker)
    //禁用播放功能
    UInt32 outputEnableFlag = 1;
    CheckError(AudioUnitSetProperty(audioUnit,
                                    kAudioOutputUnitProperty_EnableIO,
                                    kAudioUnitScope_Output,
                                    0,
                                    &outputEnableFlag,
                                    sizeof(outputEnableFlag)),
               "Open output of bus 0 failed");
    //Set up stream format for input and output
    streamFormat.mFormatID = kAudioFormatLinearPCM;
    streamFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    streamFormat.mSampleRate = kRate;
    streamFormat.mFramesPerPacket = 1;
    streamFormat.mBytesPerFrame = 2;
    streamFormat.mBytesPerPacket = 2;
    streamFormat.mBitsPerChannel = kBits;
    streamFormat.mChannelsPerFrame = kChannels;
    
    
    CheckError(AudioUnitSetProperty(audioUnit,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Input,
                                    0,
                                    &streamFormat,
                                    sizeof(streamFormat)),
               "kAudioUnitProperty_StreamFormat of bus 0 failed");
    CheckError(AudioUnitSetProperty(audioUnit,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Output,
                                    1,
                                    &streamFormat,
                                    sizeof(streamFormat)),
               "kAudioUnitProperty_StreamFormat of bus 1 failed");
    
    //音频采集结果回调
    AURenderCallbackStruct recordCallback;
    recordCallback.inputProc = recordCallback_xb;
    recordCallback.inputProcRefCon = (__bridge void *)(self);
    CheckError(AudioUnitSetProperty(audioUnit,
                                    kAudioOutputUnitProperty_SetInputCallback,
                                    kAudioUnitScope_Output,
                                    1,
                                    &recordCallback,
                                    sizeof(recordCallback)),
               "couldnt set remote i/o render callback for output");
    AURenderCallbackStruct playCallback;
    playCallback.inputProc = playCallback_xb;
    playCallback.inputProcRefCon = (__bridge void *)(self);
    CheckError(AudioUnitSetProperty(audioUnit,
                                    kAudioUnitProperty_SetRenderCallback,
                                    kAudioUnitScope_Input,
                                    0,
                                    &playCallback,
                                    sizeof(playCallback)),
               "kAudioUnitProperty_SetRenderCallback failed");
    
}


static void CheckError(OSStatus error, const char *operation)
{
    if (error == noErr) return;
    char errorString[20];
    // See if it appears to be a 4-char-code
    *(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(error);
    if (isprint(errorString[1]) && isprint(errorString[2]) &&
        isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    } else
        // No, format it as an integer
        sprintf(errorString, "%d", (int)error);
    fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
    exit(1);
}

//设置音频
- (void)setupAudioInput {

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
    _videoConnection = [videoOutput connectionWithMediaType:AVMediaTypeVideo];
    _videoConnection.videoOrientation = AVCaptureVideoOrientationPortrait;
    _videoConnection.videoMirrored = YES;
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
AVCodec* decode_codec = NULL;
AVCodecContext *decode_codec_ctx = NULL;
AVFrame *decode_aacFrame=NULL;
AVPacket decode_aacPacket;

int init_decode_audio()
{
    av_register_all();
    decode_codec = avcodec_find_decoder(AV_CODEC_ID_AAC);
    if (!decode_codec)
    {
        fprintf(stderr, "codec not found\n");
        exit(1);
    }
    
    decode_codec_ctx = avcodec_alloc_context3(decode_codec);
    decode_codec_ctx->codec_type = AVMEDIA_TYPE_AUDIO;
    decode_codec_ctx->sample_rate = kRate;
    decode_codec_ctx->channels = kChannels;
    decode_codec_ctx->bit_rate = 64 * 1000;
    decode_codec_ctx->channel_layout = AV_CH_LAYOUT_STEREO;
    
    if (avcodec_open2(decode_codec_ctx, decode_codec,NULL) < 0)
    {
        fprintf(stderr, "could not open codec\n");
        exit(1);
    }
    decode_aacFrame = av_frame_alloc();
    return 1;
}

int decode_audio(int length,uint8_t*acc_data)
{
    decode_aacPacket.data = acc_data;
    decode_aacPacket.size = length;
    if(&decode_aacPacket)
    {
        avcodec_send_packet(decode_codec_ctx, &decode_aacPacket);
        int result = avcodec_receive_frame(decode_codec_ctx,decode_aacFrame);
        if (result == 0) {
            struct SwrContext *au_convert_ctx = swr_alloc();
            au_convert_ctx = swr_alloc_set_opts(au_convert_ctx,
                                                AV_CH_LAYOUT_STEREO, AV_SAMPLE_FMT_S16, kRate,
                                               decode_codec_ctx->channel_layout, decode_codec_ctx->sample_fmt, decode_codec_ctx->sample_rate,
                                                0, NULL);
            swr_init(au_convert_ctx);
            int out_linesize;
            int out_buffer_size=av_samples_get_buffer_size(&out_linesize,decode_codec_ctx->channels,decode_codec_ctx->frame_size,decode_codec_ctx->sample_fmt, 1);
            uint8_t *out_buffer=(uint8_t *)av_malloc(out_buffer_size);
            swr_convert(au_convert_ctx, &out_buffer, out_linesize, (const uint8_t **)decode_aacFrame->data , decode_aacFrame->nb_samples);
            
            swr_free(&au_convert_ctx);
            au_convert_ctx = NULL;
            printf("out_linesize:%d\n",out_linesize);
//            tcp_send(cbase->sfd, , out_linesize);
            // 释放
            av_free(out_buffer);
        }
    }
    return 1;
}

int encode_audio(char *pcm_data,int size)
{
    uint8_t m_aacOutbuf[1024];
    AACENC_BufDesc in_buf = { 0 }, out_buf = { 0 };
    AACENC_InArgs in_args = { 0 };
    AACENC_OutArgs out_args = { 0 };
    int in_identifier = IN_AUDIO_DATA;
    int in_elem_size = 2;
    in_args.numInSamples = size / 2;  //size为pcm字节数
    in_buf.numBufs = 1;
    in_buf.bufs = &pcm_data;  //pData为pcm数据指针
    in_buf.bufferIdentifiers = &in_identifier;
    in_buf.bufSizes = &size;
    in_buf.bufElSizes = &in_elem_size;
    
    int out_identifier = OUT_BITSTREAM_DATA;
    void *out_ptr = m_aacOutbuf;
    int out_size = sizeof(m_aacOutbuf);
    int out_elem_size = 1;
    out_buf.numBufs = 1;
    out_buf.bufs = &out_ptr;
    out_buf.bufferIdentifiers = &out_identifier;
    out_buf.bufSizes = &out_size;
    out_buf.bufElSizes = &out_elem_size;
    
    if ((aacEncEncode(audio_encoder, &in_buf, &out_buf, &in_args, &out_args)) != AACENC_OK) {
//        fprintf(stderr, "Encoding aac failed\n");
        printf("acc::aacEncEncode fail\n");
        return -1;
    }
    if (out_args.numOutBytes == 0)
    {
         printf("acc::aacEncEncode fail-1\n");
         return -1;
    }else{
         printf("acc::size %d\n",out_args.numOutBytes);
//        tcp_send(cbase->sfd,m_aacOutbuf, out_args.numOutBytes);
        decode_audio(out_args.numOutBytes,m_aacOutbuf);
    }
    return 1;
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if( connection == _videoConnection) //视频
    {
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        CIImage *ciImage = [CIImage imageWithCVImageBuffer:imageBuffer];
        UIImage *image = [UIImage imageWithCIImage:ciImage];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.recording_view.image = image;
            
        });
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
            if(tcp_send_status == 0x02)
            {
               // tcp_send(cbase->sfd,yuv_frame,uv_size + y_size);
            }
            encoder->yuv420p_picture->i_pts++; //一帧的显示时间
            encoder->yuv420p_picture->img.plane[0] =yuv_frame;
            encoder->yuv420p_picture->img.plane[1] =yuv_frame+IMAGE_WIDTH*IMAGE_HEIGHT;    //u数据的首地址
            encoder->yuv420p_picture->img.plane[2] = yuv_frame+IMAGE_WIDTH*IMAGE_HEIGHT+IMAGE_WIDTH*IMAGE_HEIGHT/4; //v数
            encoder->nal = (x264_nal_t *)malloc(sizeof(x264_nal_t));
            if(!encoder->nal){
                log_print("malloc x264_nal_t error!\n");
                free(encoder->nal);
                encoder->nal = NULL;
                exit(EXIT_FAILURE);
            }
            CLEAR(*(encoder->nal));
            x264_picture_t pic_out;
            x264_nal_t *my_nal;
            int ret = x264_encoder_encode(encoder->x264_encoder,&encoder->nal,&encoder->n_nal,encoder->yuv420p_picture,&pic_out);
            if(ret<0)
            {
                log_print("x264_encoder_encode error!\n");
                exit(EXIT_FAILURE);
            }
            for(my_nal = encoder->nal; my_nal<encoder->nal+encoder->n_nal; ++my_nal){
                ffmpeg(my_nal->i_payload, my_nal->p_payload);
            }
            free(yuv_frame);
            yuv_frame = NULL;
            CVPixelBufferUnlockBaseAddress(imageBuffer,0);
        });
    }
   
}

@end
