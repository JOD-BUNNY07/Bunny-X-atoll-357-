#ifndef __KSU_H_SUCOMPAT
#define __KSU_H_SUCOMPAT
#include <asm/ptrace.h>
#include <linux/types.h>

extern bool ksu_su_compat_enabled;

void ksu_sucompat_init(void);
void ksu_sucompat_exit(void);

// Handler functions exported for hook_manager
long ksu_handle_faccessat_sucompat(int orig_nr, struct pt_regs *regs);
long ksu_handle_stat_sucompat(int orig_nr, struct pt_regs *regs);
long ksu_handle_execve_sucompat(const char __user **filename_user, int orig_nr, struct pt_regs *regs);
long ksu_handle_execveat_sucompat(const char __user **filename_user, int orig_nr, struct pt_regs *regs);

#ifdef CONFIG_KSU_MANUAL_HOOK
// Manual-hook entry points, called from the patched kernel source.
int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode, int *__unused_flags);
int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);
int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags);
#endif

#endif
