#include "linux/file.h"
#include "linux/fcntl.h"
#include "linux/namei.h"
#include <linux/compiler_types.h>
#include <linux/binfmts.h>
#include <linux/preempt.h>
#include <linux/printk.h>
#include <linux/mm.h>
#include <linux/pgtable.h>
#include <linux/uaccess.h>
#include <asm/current.h>
#include <linux/cred.h>
#include <linux/fs.h>
#include <linux/types.h>
#include <linux/version.h>
#include <linux/sched/task_stack.h>
#include <linux/ptrace.h>

#include "arch.h"
#include "policy/allowlist.h"
#include "policy/feature.h"
#include "klog.h" // IWYU pragma: keep
#include "runtime/ksud.h"
#include "feature/sucompat.h"
#include "policy/app_profile.h"
#include "hook/syscall_hook.h"
#include "supercall/supercall.h"
#include "sulog/event.h"
#include "ksu.h"
#include "util.h"

#define SU_PATH "/system/bin/su"
#define SH_PATH "/system/bin/sh"

bool ksu_su_compat_enabled __read_mostly = true;

static int su_compat_feature_get(u64 *value)
{
    *value = ksu_su_compat_enabled ? 1 : 0;
    return 0;
}

static int su_compat_feature_set(u64 value)
{
    bool enable = value != 0;
    ksu_su_compat_enabled = enable;
    pr_info("su_compat: set to %d\n", enable);
    return 0;
}

static const struct ksu_feature_handler su_compat_handler = {
    .feature_id = KSU_FEATURE_SU_COMPAT,
    .name = "su_compat",
    .get_handler = su_compat_feature_get,
    .set_handler = su_compat_feature_set,
};

static char __user *ksud_user_path(void)
{
    static const char ksud_path[] = KSUD_PATH;

    return userspace_stack_buffer(ksud_path, sizeof(ksud_path));
}

static char __user *empty_user_path(void)
{
    return userspace_stack_buffer("", sizeof(""));
}

#ifndef CONFIG_KSU_TRACEPOINT_HOOK
/*
 * Manual-hook path: the kernel call sites pass kernel pointers instead of a
 * pt_regs frame, so we rewrite the filename in place.  Adapted from BakaSU
 * (https://github.com/Baka-SU/BakaSU), kernel/feature/sucompat.c.
 */
static char __user *sh_user_path(void)
{
    static const char sh_path[] = SH_PATH;

    return userspace_stack_buffer(sh_path, sizeof(sh_path));
}
#endif

static const char su_path[] = SU_PATH;

static bool is_ksud_exists()
{
    struct path path;

    if (kern_path(KSUD_PATH, 0, &path) < 0) {
        return false;
    }
    path_put(&path);
    return true;
}

long ksu_handle_faccessat_sucompat(int orig_nr, struct pt_regs *regs)
{
    const char __user **filename_user, *orig_filename;
    long ret;
    const struct cred *old_cred;

    if (!ksu_is_allow_uid_for_current(current_uid().val)) {
        goto do_orig_facessat;
    }

    filename_user = (const char __user **)&PT_REGS_PARM2(regs);

    char path[sizeof(su_path) + 1];
    memset(path, 0, sizeof(path));
    ksu_strncpy_from_user_nofault(path, *filename_user, sizeof(path));

    if (unlikely(!memcmp(path, su_path, sizeof(su_path)))) {
        old_cred = override_creds(ksu_cred);
        if (is_ksud_exists()) {
            pr_info("faccessat su->ksud!\n");
            orig_filename = *filename_user;
            *filename_user = ksud_user_path();
            ret = ksu_syscall_table[orig_nr](regs);
            revert_creds(old_cred);
            *filename_user = orig_filename;
            return ret;
        } else {
            revert_creds(old_cred);
        }
    }

do_orig_facessat:
    return ksu_syscall_table[orig_nr](regs);
}

long ksu_handle_stat_sucompat(int orig_nr, struct pt_regs *regs)
{
    const char __user **filename_user, *orig_filename;
    long ret;
    const struct cred *old_cred;

    if (!ksu_is_allow_uid_for_current(current_uid().val)) {
        goto do_orig_stat;
    }

    filename_user = (const char __user **)&PT_REGS_PARM2(regs);

    char path[sizeof(su_path) + 1];
    memset(path, 0, sizeof(path));
    ksu_strncpy_from_user_nofault(path, *filename_user, sizeof(path));

    if (unlikely(!memcmp(path, su_path, sizeof(su_path)))) {
        old_cred = override_creds(ksu_cred);
        if (is_ksud_exists()) {
            pr_info("newfstatat su->ksud!\n");
            orig_filename = *filename_user;
            *filename_user = ksud_user_path();
            ret = ksu_syscall_table[orig_nr](regs);
            revert_creds(old_cred);
            *filename_user = orig_filename;
            return ret;
        } else {
            revert_creds(old_cred);
        }
    }

do_orig_stat:
    return ksu_syscall_table[orig_nr](regs);
}

static long ksu_handle_execve_sucompat_common(const char __user **filename_user,
                                              const char __user *const __user *argv_user, unsigned long envp,
                                              bool execveat, int orig_nr, struct pt_regs *regs)
{
    const char __user *fn;
    struct ksu_sulog_pending_event *pending_sucompat = NULL;
    char path[sizeof(su_path) + 1];
    long ret, orig_regs[5];
    unsigned long addr;
    int su_fd = -1;
    int tmp_fd;
    struct file *ksud_file;
    const struct cred *old_cred;

    if (execveat && ((int)PT_REGS_SYSCALL_PARM1(regs) != AT_FDCWD || (int)PT_REGS_PARM5(regs) != 0))
        goto do_orig_execve;

    if (unlikely(!filename_user))
        goto do_orig_execve;

    if (!ksu_is_allow_uid_for_current(current_uid().val))
        goto do_orig_execve;

    addr = untagged_addr((unsigned long)*filename_user);
    fn = (const char __user *)addr;
    memset(path, 0, sizeof(path));

    ret = strncpy_from_user(path, fn, sizeof(path));

    if (ret < 0) {
        pr_warn("Access filename when execve failed: %ld", ret);
        goto do_orig_execve;
    }

    if (likely(memcmp(path, su_path, sizeof(su_path))))
        goto do_orig_execve;

    pr_info("sys_execve su found\n");

    tmp_fd = get_unused_fd_flags(O_CLOEXEC);
    if (tmp_fd < 0) {
        pr_err("alloc tmp fd err: %d\n", tmp_fd);
        goto do_orig_execve;
    }

    old_cred = override_creds(ksu_cred);
    ksud_file = filp_open(KSUD_PATH, O_PATH, 0);
    revert_creds(old_cred);
    if (IS_ERR(ksud_file)) {
        pr_err("open ksud err: %ld\n", PTR_ERR(ksud_file));
        put_unused_fd(tmp_fd);
        goto do_orig_execve;
    }

    fd_install(tmp_fd, ksud_file);

    pending_sucompat = ksu_sulog_capture_sucompat(*filename_user, argv_user, GFP_KERNEL);
    // execve(file, argv, environ)
    // execveat(fd, file, argv, environ, flags)
    orig_regs[0] = PT_REGS_SYSCALL_PARM1(regs);
    orig_regs[1] = regs->__PT_PARM2_REG;
    orig_regs[2] = regs->__PT_PARM3_REG;
    orig_regs[3] = regs->__PT_SYSCALL_PARM4_REG;
    orig_regs[4] = regs->__PT_PARM5_REG;
    regs->__PT_PARM5_REG = AT_EMPTY_PATH;
    regs->__PT_SYSCALL_PARM4_REG = envp;
    regs->__PT_PARM3_REG = (unsigned long)argv_user;
    regs->__PT_PARM2_REG = empty_user_path();
    PT_REGS_SYSCALL_PARM1(regs) = tmp_fd;

    ret = escape_with_root_profile();
    if (ret) {
        pr_err("escape_with_root_profile failed: %ld\n", ret);
    }
    ksu_sulog_emit_pending(pending_sucompat, ret, GFP_KERNEL);

    ret = ksu_syscall_table[__NR_execveat](regs);
    if (ret < 0) {
        ksu_close_fd(tmp_fd);
        PT_REGS_SYSCALL_PARM1(regs) = orig_regs[0];
        regs->__PT_PARM2_REG = orig_regs[1];
        regs->__PT_PARM3_REG = orig_regs[2];
        regs->__PT_SYSCALL_PARM4_REG = orig_regs[3];
        regs->__PT_PARM5_REG = orig_regs[4];
    } else {
        // Only grant the scoped driver capability after the selected root
        // profile has been applied successfully.
        su_fd = ksu_install_su_fd();
        if (su_fd < 0) {
            pr_warn("install su session fd failed: %d\n", su_fd);
        }
    }
    return ret;

do_orig_execve:
    return ksu_syscall_table[orig_nr](regs);
}

long ksu_handle_execve_sucompat(const char __user **filename_user, int orig_nr, struct pt_regs *regs)
{
    return ksu_handle_execve_sucompat_common(filename_user, (const char __user *const __user *)PT_REGS_PARM2(regs),
                                             PT_REGS_PARM3(regs), false, orig_nr, regs);
}

long ksu_handle_execveat_sucompat(const char __user **filename_user, int orig_nr, struct pt_regs *regs)
{
    return ksu_handle_execve_sucompat_common(filename_user, (const char __user *const __user *)PT_REGS_PARM3(regs),
                                             PT_REGS_SYSCALL_PARM4(regs), true, orig_nr, regs);
}

#ifndef CONFIG_KSU_TRACEPOINT_HOOK
/*
 * Manual hook entry points.  These are called from the patched kernel source
 * (see tools/manual_hook_check.mk and docs/old-kernels.md).
 */
int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode, int *__unused_flags)
{
    char path[sizeof(su_path) + 1] = { 0 };
    const struct cred *old_cred;

    if (!ksu_su_compat_enabled)
        return 0;

    if (!ksu_is_allow_uid_for_current(current_uid().val))
        return 0;

    if (!filename_user || !*filename_user)
        return 0;

    ksu_strncpy_from_user_nofault(path, *filename_user, sizeof(path));

    if (unlikely(!memcmp(path, su_path, sizeof(su_path)))) {
        old_cred = override_creds(ksu_cred);
        if (is_ksud_exists()) {
            pr_info("ksu_handle_faccessat su->sh!\n");
            *filename_user = sh_user_path();
        } else {
            pr_info("no ksud found, don't process faccessat for su!\n");
        }
        revert_creds(old_cred);
    }

    return 0;
}

int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags)
{
    char path[sizeof(su_path) + 1] = { 0 };
    const struct cred *old_cred;

    if (!ksu_su_compat_enabled)
        return 0;

    if (!ksu_is_allow_uid_for_current(current_uid().val))
        return 0;

    if (!filename_user || !*filename_user)
        return 0;

    ksu_strncpy_from_user_nofault(path, *filename_user, sizeof(path));

    if (unlikely(!memcmp(path, su_path, sizeof(su_path)))) {
        old_cred = override_creds(ksu_cred);
        if (is_ksud_exists()) {
            pr_info("ksu_handle_stat su->sh!\n");
            *filename_user = sh_user_path();
        } else {
            pr_info("no ksud found, don't process stat for su!\n");
        }
        revert_creds(old_cred);
    }

    return 0;
}

int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags)
{
    struct filename *filename;
    struct user_arg_ptr uargv = { .ptr.native = (const char __user *const __user *)argv };
    const struct cred *old_cred;

    if (!filename_ptr)
        return 0;

    filename = *filename_ptr;
    if (IS_ERR_OR_NULL(filename) || !filename->name)
        return 0;

    // Only the plain execve()/execveat(AT_FDCWD, ..., 0) case is redirected.
    if (fd && *fd != AT_FDCWD)
        return 0;
    if (flags && *flags != 0)
        return 0;

    // Keep the existing ksud/init/zygote bookkeeping.
    ksu_handle_execveat_ksud(filename->name, &uargv);

    if (!ksu_su_compat_enabled)
        return 0;

    if (!ksu_is_allow_uid_for_current(current_uid().val))
        return 0;

    if (likely(memcmp(filename->name, su_path, sizeof(su_path))))
        return 0;

    old_cred = override_creds(ksu_cred);
    if (!is_ksud_exists()) {
        pr_info("no ksud found, don't process execve for su!\n");
        revert_creds(old_cred);
        return 0;
    }
    revert_creds(old_cred);

    pr_info("do_execveat_common su found\n");

    escape_with_root_profile();
    // KSUD_PATH and SU_PATH have the same length, so this stays in place.
    memcpy((void *)filename->name, KSUD_PATH, sizeof(KSUD_PATH));

    return 0;
}

void ksu_stop_ksud_execve_hook(void)
{
    // No static key in manual mode: the kernel call site stays in place.
}
#endif // !CONFIG_KSU_TRACEPOINT_HOOK

// sucompat: permitted process can execute 'su' to gain root access.
void __init ksu_sucompat_init()
{
    if (ksu_register_feature_handler(&su_compat_handler)) {
        pr_err("Failed to register su_compat feature handler\n");
    }
}

void __exit ksu_sucompat_exit()
{
    ksu_unregister_feature_handler(KSU_FEATURE_SU_COMPAT);
}
