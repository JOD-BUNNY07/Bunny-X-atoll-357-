#ifndef __KSU_H_KSUD
#define __KSU_H_KSUD

#include <asm/syscall.h>
#include <linux/fs.h>
#include <linux/stat.h>
#include <linux/types.h>

#define KSUD_PATH "/data/adb/ksud"

struct user_arg_ptr;

void ksu_ksud_init();
void ksu_ksud_exit();

void ksu_execve_hook_ksud(const struct pt_regs *regs);
void ksu_execveat_hook_ksud(const struct pt_regs *regs);
void ksu_handle_execveat_ksud(const char *path, struct user_arg_ptr *argv);
void ksu_stop_input_hook_runtime(void);

int ksu_handle_sys_read(unsigned int fd, char __user **buf_ptr, size_t *count_ptr);
int ksu_handle_input_handle_event(unsigned int *type, unsigned int *code, int *value);
void ksu_handle_initrc(struct file *file);

#ifdef CONFIG_KSU_MANUAL_HOOK
void ksu_handle_newfstat_ret(unsigned int *fd, struct stat __user **statbuf_ptr);
#if defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_COMPAT_STAT64)
void ksu_handle_fstat64_ret(unsigned long *fd, struct stat64 __user **statbuf_ptr);
#endif
#endif

#endif
