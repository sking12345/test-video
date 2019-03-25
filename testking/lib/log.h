#ifndef _LOG_H_
#define _LOG_H_
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
/**
 * [log 日志]
 * @param info      [description]
 * @param file_name [description]
 * @param line      [description]
 */
void log_debug(const char *info, const char *file_name, int line, const char *function_name);
void log_print(const char *info);

#endif