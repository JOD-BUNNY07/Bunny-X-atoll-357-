/*
 * Built-in LSM hooks for manual-hook mode.
 *
 * Adapted from BakaSU (https://github.com/Baka-SU/BakaSU),
 * kernel/hook/lsm_hooks.c.  KazeSU's tracepoint build does not use these;
 * they are only compiled when CONFIG_KSU_MANUAL_HOOK is selected and replace
 * the kernel-source patches for setresuid and init.rc reads.  Kernels older
 * than 4.2 have no security_add_hooks(), so those call sites must be patched
 * by hand (see docs/old-kernels.md).
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

#include <linux/version.h>
#include <linux/security.h>
#include <linux/init.h>
#include <linux/sched.h>
#include <linux/cred.h>
#include <linux/key.h>
#include <linux/string.h>
#include <linux/kernel.h>
#include <linux/uidgid.h>
#include <linux/task_work.h>
#include <linux/dcache.h>
#include <linux/fs.h>

#include "manager/throne_tracker.h"
#include "compat/kernel_compat.h"
#include "feature/sucompat.h"
#include "hook/lsm_hooks.h"
#include "hook/setuid_hook.h"
#include "runtime/ksud.h"
#include "ksu.h"
#include "klog.h"

/*
 * security_add_hooks() and the hook-list interface arrived in 4.2.  On older
 * trees everything below is dead code and the call sites have to be patched
 * directly, so keep the whole block behind the version check to avoid
 * "defined but not used" warnings.
 */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 2, 0) || defined(KSU_COMPAT_HAS_LIST_OF_LSM_HOOKS)

#ifdef CONFIG_KSU_MANUAL_HOOK_AUTO_SETUID_HOOK
static int ksu_task_fix_setuid(struct cred *new, const struct cred *old, int flags)
{
    return ksu_handle_setresuid(ksu_get_uid_t(old->uid), ksu_get_uid_t(new->uid));
}
#endif

#ifdef CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK
static int ksu_file_permission(struct file *file, int mask)
{
    ksu_handle_initrc(file);
    return 0;
}
#endif

/*
 * On kernels before 6.8 the fsnotify packages.list observer is fragile, so
 * use the inode_rename LSM hook to notice the manager APK moving into place
 * and rescan from task_work, after the rename's locks are dropped.
 */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 8, 0)
static void ksu_track_throne_tw_func(struct callback_head *cb)
{
    kfree(cb);
    if (current->flags & PF_EXITING)
        return;
    track_throne(false);
}

static void ksu_defer_track_throne(void)
{
    struct callback_head *cb;

    if (current->flags & PF_KTHREAD)
        return;

    cb = kzalloc(sizeof(*cb), GFP_ATOMIC);
    if (!cb)
        return;

    cb->func = ksu_track_throne_tw_func;
    if (task_work_add(current, cb, TWA_RESUME))
        kfree(cb);
}

static int ksu_inode_rename(struct inode *old_inode, struct dentry *old_dentry, struct inode *new_inode,
                            struct dentry *new_dentry)
{
    const char *name;

    if (!new_dentry)
        return 0;

    name = new_dentry->d_name.name;
    if (new_dentry->d_name.len == 13 && name && !memcmp(name, "packages.list", 13))
        ksu_defer_track_throne();

    return 0;
}

int ksu_observer_init(void)
{
    return 0;
}

void ksu_observer_exit(void)
{
}
#endif // < 6.8

static int ksu_handle_key_permission(key_ref_t key_ref, const struct cred *cred,
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 8, 0) || defined(KSU_COMPAT_KEY_NEED_PERM_AS_ENUM)
                                     enum key_need_perm need_perm)
#else
                                     unsigned int perm)
#endif
{
    if (init_session_keyring != NULL)
        return 0;

    if (strcmp(current->comm, "init"))
        return 0;

    init_session_keyring = ksu_get_session_keyring(cred);
    if (!init_session_keyring)
        return 0;

    pr_info("%s: got init_session_keyring, installing into ksu_cred\n", __func__);
    setup_ksu_cred_session_keyring();
    return 0;
}

static struct security_hook_list ksu_hooks[] = {
#ifdef CONFIG_KSU_MANUAL_HOOK_AUTO_SETUID_HOOK
    LSM_HOOK_INIT(task_fix_setuid, ksu_task_fix_setuid),
#endif
#ifdef CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK
    LSM_HOOK_INIT(file_permission, ksu_file_permission),
#endif
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 8, 0)
    LSM_HOOK_INIT(inode_rename, ksu_inode_rename),
#endif
    LSM_HOOK_INIT(key_permission, ksu_handle_key_permission),
};

void __init ksu_lsm_hook_built_in_init(void)
{
    // https://github.com/torvalds/linux/commit/d69dece5f5b6bc7a5e39d2b6136ddc69469331fe
#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 11, 0) || defined(KSU_COMPAT_REQUIRE_PROVIDE_LSM_NAME)
    security_add_hooks(ksu_hooks, ARRAY_SIZE(ksu_hooks), "ksu");
#else
    // https://elixir.bootlin.com/linux/v4.10.17/source/include/linux/lsm_hooks.h#L1892
    security_add_hooks(ksu_hooks, ARRAY_SIZE(ksu_hooks));
#endif
}

#else // < 4.2

void __init ksu_lsm_hook_built_in_init(void)
{
    pr_warn("lsm_hooks: security_add_hooks() needs Linux 4.2+; "
            "hook setresuid/read/faccessat/stat manually\n");
}

#endif // >= 4.2
