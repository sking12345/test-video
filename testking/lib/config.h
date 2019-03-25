#ifndef CONFIG_H
#define CONFIG_H


// #define COMPILE_TYPE 0x00	//编译方式 0x00:服务端
#define COMPILE_TYPE 0x01  //客户端


#define SERVER_MAX_CONNECT_NUM 100	//服务器最大连接数

#define TCP_APK_SIZE 1420	//根据tcp 的一个包大小 减去 struct apk 关键字段大小 设置

//是否等待完整的数据
#define TCP_DATA_COMPLETE 0x00 //不等待完整的数据，直接调用回调，用于即时通信转发

// #define TCP_DATA_COMPLETE 0x01 //等待完整的数据,

#endif

