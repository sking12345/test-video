#ifndef _SOCKET_H_
#define _SOCKET_H_

#include "config.h"
#include<stdio.h>
#include<errno.h>
#include<unistd.h>
#include<string.h>
#include <stdlib.h>
#include "log.h"
#include "thread_pool.h"
#include <netinet/in.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <string.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>

#define APK_NOT_END 0x00
#define APK_END 0x01
#define APK_CONFIRM 0x02

typedef struct sockaddr SA;

//数据包分别结构
typedef struct apk_buf {
	int size;
	int number;
	int status;
	char only_number[16];	//数据唯一编号,struct send_queue 的编号一样,用于服务器确认接受到的什么数据
	char buf[TCP_APK_SIZE];
} apk_buf_t;
typedef struct read_buf
{
	int cfd;
#if COMPILE_TYPE == 0x00
	struct server_base * base;
#else
	struct client_base *base;
#endif
	char buf[0];
} read_buf_t;

int tcp_send(int fd, void *, int size);

#if COMPILE_TYPE == 0x00
#include<event.h>

typedef struct server_base {
	int close;
	int max_connect;
	int connect_num;	//服务器连接数据
	struct event_base*base;
	struct event*ev_listen;
	void* (*new_accept)(int cfd);
	void* (*abnormal)(int cfd);
	void* (*read_call)(int cfd, void * read_buf, struct server_base *base);
	struct thread_pool *thread_pool;
	void *arg;
	char * conencts_info;
} server_base_t;

typedef struct accepts_event {
	int cfd;
	int status;
	int size;
	struct event *evt;
	char *recv_buf;
} server_accept_t;




void accept_cb(int fd, short events, void* arg);
void socket_read_cb(int fd, short events, void *arg);

struct server_base* tcp_server_init(int port, int listen_num, int max_connect, void *arg);

int tcp_server_start(struct server_base*, struct thread_pool *, void* (*new_accept)(int cfd),
                     void* (*abnormal)(int cfd),
                     void* (*read_call)(int cfd, void * read_buf, struct server_base *base));

void tcp_server_end(struct server_base**);
int tcp_server_closed(struct server_base*, int fd);
#else
typedef struct client_base {
	int sfd;
	char *ip;
	int port;
	int close; //连接状态
	struct thread_pool *thread_pool;
	void* (*abnormal)(int cfd);
	void* (*read_call)(int fd, void *recv_buf, struct client_base*cbase);
	int recv_status;
	char * recv_buf;
	void *arg;
} client_base_t;

struct client_base * tcp_client_init(const char *ip, int port);
int tcp_client_start(struct client_base *, struct thread_pool *thread_pool, void* (*abnormal)(int cfd), void* (*read_call)(int fd, void *recv_buf, struct client_base*cbase));
void tcp_client_end(struct client_base **);
int tcp_client_closed(struct client_base*);
#endif


#endif
































