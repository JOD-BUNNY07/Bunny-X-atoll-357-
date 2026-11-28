#include "compat/kernel_compat.h"
#include "linux/rcupdate.h"
#include "security.h"
#include <linux/uaccess.h>
#include <linux/types.h>
#include <linux/version.h>
#include <linux/init.h>
#include <linux/lockdep.h>
#include <linux/rwlock.h>
#include <linux/slab.h>
#include <linux/string.h>

#include "uapi/selinux.h"
#include "klog.h" // IWYU pragma: keep
#include "selinux.h"
#include "selinux_defs.h"
#include "sepolicy.h"
#include "ss/services.h"
#include "linux/lsm_audit.h" // IWYU pragma: keep
#include "xfrm.h"
#include "infra/symbol_resolver.h"

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0) || defined(KSU_COMPAT_HAS_POLICY_MUTEX)
#define SELINUX_POLICY_INSTEAD_SELINUX_SS

struct selinux_policy *backup_sepolicy;
#endif

#define ALL NULL

#if ((!defined(KSU_COMPAT_USE_SELINUX_STATE)) || LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
extern int avc_ss_reset(u32 seqno);
#else
extern int avc_ss_reset(struct selinux_avc *avc, u32 seqno);
#endif
// reset avc cache table, otherwise the new rules will not take effect if already denied
static void reset_avc_cache(u32 seqno)
{
#if ((!defined(KSU_COMPAT_USE_SELINUX_STATE)) || LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
    avc_ss_reset(seqno);
    selnl_notify_policyload(seqno);
    selinux_status_update_policyload(seqno);
#else
    struct selinux_avc *avc = selinux_state.avc;
    avc_ss_reset(avc, seqno);
    selnl_notify_policyload(seqno);
    selinux_status_update_policyload(&selinux_state, seqno);
#endif
    selinux_xfrm_notify_policyload();
}

#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 10, 0) && !defined(KSU_COMPAT_HAS_POLICY_MUTEX)
/*
 * Legacy (pre-5.10) policy plumbing.
 *
 * Adapted from BakaSU (https://github.com/Baka-SU/BakaSU),
 * kernel/selinux/rules.c.
 */

static struct mutex *ksu_sel_mutex_ptr = NULL;
rwlock_t *ksu_policy_rwlock_ptr = NULL;
static u32 *latest_granting_ptr = NULL;

static struct policydb *get_policydb(void)
{
#ifdef KSU_COMPAT_USE_SELINUX_STATE
    return &selinux_state.ss->policydb;
#else
    return &policydb;
#endif
}

static inline void ksu_lock_sel_mutex_legacy(void)
{
#ifdef KSU_COMPAT_USE_SELINUX_STATE
    /*
     * 4.17-5.9 keep the selinuxfs serialization mutex private to
     * selinuxfs.c.  We cannot reach it, and the rules are applied early
     * (init's second stage) before userspace can reload the policy.
     */
#else
    if (ksu_sel_mutex_ptr)
        mutex_lock(ksu_sel_mutex_ptr);
#endif
}

static inline void ksu_unlock_sel_mutex_legacy(void)
{
#ifdef KSU_COMPAT_USE_SELINUX_STATE
#else
    if (ksu_sel_mutex_ptr)
        mutex_unlock(ksu_sel_mutex_ptr);
#endif
}

static inline void ksu_lock_sepolicy_legacy(void)
{
#ifdef KSU_COMPAT_USE_SELINUX_STATE
    write_lock_irq(&selinux_state.ss->policy_rwlock);
#else
    if (ksu_policy_rwlock_ptr)
        write_lock_irq(ksu_policy_rwlock_ptr);
#endif
}

static inline void ksu_unlock_sepolicy_legacy(void)
{
#ifdef KSU_COMPAT_USE_SELINUX_STATE
    write_unlock_irq(&selinux_state.ss->policy_rwlock);
#else
    if (ksu_policy_rwlock_ptr)
        write_unlock_irq(ksu_policy_rwlock_ptr);
#endif
}
#endif // legacy policy plumbing

void __init ksu_selinux_init(void)
{
#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 17, 0) && !defined(KSU_COMPAT_USE_SELINUX_STATE)
    ksu_sel_mutex_ptr = ksu_resolve_symbol_for_functable_hook("sel_mutex");
    ksu_policy_rwlock_ptr = ksu_resolve_symbol_for_functable_hook("policy_rwlock");
    latest_granting_ptr = ksu_resolve_symbol_for_functable_hook("latest_granting");

    if (!ksu_policy_rwlock_ptr || !latest_granting_ptr)
        pr_warn("selinux: legacy policy symbols not found, policy edits may race\n");
#endif
}

static void ksu_apply_rule_set(struct policydb *db)
{
    ksu_type(db, KERNEL_SU_DOMAIN, "domain");
    ksu_permissive(db, KERNEL_SU_DOMAIN);
    ksu_typeattribute(db, KERNEL_SU_DOMAIN, "mlstrustedsubject");
    ksu_typeattribute(db, KERNEL_SU_DOMAIN, "netdomain");
    ksu_typeattribute(db, KERNEL_SU_DOMAIN, "bluetoothdomain");

    // Create unconstrained file type
    ksu_type(db, KERNEL_SU_FILE, "file_type");
    ksu_typeattribute(db, KERNEL_SU_FILE, "mlstrustedobject");
    ksu_allow(db, "domain", KERNEL_SU_FILE, ALL, ALL);

    // allow all!
    ksu_allow(db, KERNEL_SU_DOMAIN, ALL, ALL, ALL);

    // allow us do any ioctl
    if (db->policyvers >= POLICYDB_VERSION_XPERMS_IOCTL) {
        ksu_allowxperm(db, KERNEL_SU_DOMAIN, ALL, "blk_file", ALL);
        ksu_allowxperm(db, KERNEL_SU_DOMAIN, ALL, "fifo_file", ALL);
        ksu_allowxperm(db, KERNEL_SU_DOMAIN, ALL, "chr_file", ALL);
        ksu_allowxperm(db, KERNEL_SU_DOMAIN, ALL, "file", ALL);
    }

    // our ksud triggered by init
    ksu_allow(db, "init", KERNEL_SU_DOMAIN, ALL, ALL);

    // copied from Magisk rules
    // suRights
    ksu_allow(db, "servicemanager", KERNEL_SU_DOMAIN, "dir", "search");
    ksu_allow(db, "servicemanager", KERNEL_SU_DOMAIN, "dir", "read");
    ksu_allow(db, "servicemanager", KERNEL_SU_DOMAIN, "file", "open");
    ksu_allow(db, "servicemanager", KERNEL_SU_DOMAIN, "file", "read");
    ksu_allow(db, "servicemanager", KERNEL_SU_DOMAIN, "process", "getattr");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "process", "sigchld");

    // allowLog
    ksu_allow(db, "logd", KERNEL_SU_DOMAIN, "dir", "search");
    ksu_allow(db, "logd", KERNEL_SU_DOMAIN, "file", "read");
    ksu_allow(db, "logd", KERNEL_SU_DOMAIN, "file", "open");
    ksu_allow(db, "logd", KERNEL_SU_DOMAIN, "file", "getattr");

    // dumpsys, send fd
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "fd", "use");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "fifo_file", "write");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "fifo_file", "read");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "fifo_file", "open");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "fifo_file", "getattr");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "unix_stream_socket", "read");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "unix_stream_socket", "write");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "unix_stream_socket", "connectto");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "unix_stream_socket", "getopt");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "unix_stream_socket", "getattr");

    // use memfd created by su domain
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "memfd_file", "execute");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "memfd_file", "getattr");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "memfd_file", "map");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "memfd_file", "read");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "memfd_file", "write");

    // bootctl
    ksu_allow(db, "hwservicemanager", KERNEL_SU_DOMAIN, "dir", "search");
    ksu_allow(db, "hwservicemanager", KERNEL_SU_DOMAIN, "file", "read");
    ksu_allow(db, "hwservicemanager", KERNEL_SU_DOMAIN, "file", "open");
    ksu_allow(db, "hwservicemanager", KERNEL_SU_DOMAIN, "process", "getattr");

    // Allow all binder transactions
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "binder", ALL);

    // Allow system server kill su process
    ksu_allow(db, "system_server", KERNEL_SU_DOMAIN, "process", "getpgid");
    ksu_allow(db, "system_server", KERNEL_SU_DOMAIN, "process", "sigkill");
}

void apply_kernelsu_rules()
{
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0) || defined(KSU_COMPAT_HAS_POLICY_MUTEX)
    struct selinux_policy *pol, *old_pol;
    struct policydb *db;
#else
    struct policydb *db, *policydb_ptr, *oldpolicydb, *newpolicydb;
    int len;
    u32 seqno;
#endif

    if (!getenforce()) {
        pr_info("SELinux permissive or disabled, apply rules!\n");
    }

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0) || defined(KSU_COMPAT_HAS_POLICY_MUTEX)
    mutex_lock(&selinux_state.policy_mutex);

    old_pol = rcu_dereference_protected(selinux_state.policy, lockdep_is_held(&selinux_state.policy_mutex));
    backup_sepolicy = ksu_dup_sepolicy(old_pol);
    if (IS_ERR(backup_sepolicy)) {
        pr_err("failed to create backup sepolicy: %ld\n", PTR_ERR(backup_sepolicy));
        backup_sepolicy = NULL;
    } else {
        backup_sepolicy->sidtab = kzalloc(sizeof(*backup_sepolicy->sidtab), GFP_KERNEL);
        if (!backup_sepolicy->sidtab) {
            pr_err("failed to alloc backup sidtab\n");
            ksu_destroy_sepolicy(backup_sepolicy);
            backup_sepolicy = NULL;
        } else {
            int ret = policydb_load_isids(&backup_sepolicy->policydb, backup_sepolicy->sidtab);
            if (ret) {
                pr_err("failed to load isids for backup sepolicy: %d!\n", ret);
                kfree(backup_sepolicy->sidtab);
                ksu_destroy_sepolicy(backup_sepolicy);
                backup_sepolicy = NULL;
            } else {
                pr_info("backup sepolicy success! latest_granting=%d\n", backup_sepolicy->latest_granting);
            }
        }
    }
    pol = ksu_dup_sepolicy(old_pol);
    if (IS_ERR(pol)) {
        pr_err("failed to dup selinux_policy: %ld\n", PTR_ERR(pol));
        goto out_unlock;
    }

    db = &pol->policydb;

    pol->latest_granting = old_pol->latest_granting + 1;
    if (!ksu_set_original_types(db, &old_pol->policydb, pol->latest_granting))
        pr_warn("failed to save original type metadata, use backup lookups\n");

    ksu_apply_rule_set(db);

    rcu_assign_pointer(selinux_state.policy, pol);
    synchronize_rcu();
    ksu_destroy_sepolicy(old_pol);

    reset_avc_cache(pol->latest_granting);
out_unlock:
    mutex_unlock(&selinux_state.policy_mutex);
#else
    policydb_ptr = get_policydb();
    oldpolicydb = kcalloc(2, sizeof(*oldpolicydb), GFP_KERNEL);
    if (!oldpolicydb)
        return;
    newpolicydb = oldpolicydb + 1;
    db = newpolicydb;

    ksu_lock_sel_mutex_legacy();

retry:
    len = ksu_dup_policydb(policydb_ptr, db);
    if (len < 0) {
        pr_err("failed to dup policydb: %d\n", len);
        goto out_free;
    }

#if defined(KSU_COMPAT_USE_SELINUX_STATE)
    seqno = selinux_state.ss->latest_granting + 1;
#else
    seqno = latest_granting_ptr ? (*latest_granting_ptr) + 1 : 1;
#endif
    if (!ksu_set_original_types(policydb_ptr, policydb_ptr, seqno))
        pr_warn("failed to save original type metadata, use backup lookups\n");

    ksu_apply_rule_set(db);

    /* Save the old policydb to free later, then install the new one. */
    memcpy(oldpolicydb, policydb_ptr, sizeof(*policydb_ptr));

    ksu_lock_sepolicy_legacy();
#if defined(KSU_COMPAT_USE_SELINUX_STATE)
    if (selinux_state.ss->latest_granting + 1 != seqno) {
#else
    if (latest_granting_ptr && (*latest_granting_ptr) + 1 != seqno) {
#endif
        // sepolicy edited by someone else, retry
        ksu_unlock_sepolicy_legacy();
        ksu_destroy_policydb(newpolicydb);
        memset(newpolicydb, 0, sizeof(*newpolicydb));
        goto retry;
    }
#if defined(KSU_COMPAT_USE_SELINUX_STATE)
    selinux_state.ss->latest_granting = seqno;
#else
    if (latest_granting_ptr)
        *latest_granting_ptr = seqno;
#endif
    memcpy(policydb_ptr, newpolicydb, sizeof(*policydb_ptr));
    ksu_unlock_sepolicy_legacy();

    reset_avc_cache(seqno);

    ksu_destroy_policydb(oldpolicydb);

out_free:
    kfree(oldpolicydb);
    ksu_unlock_sel_mutex_legacy();
#endif
}

#define KSU_SEPOLICY_MAX_BATCH_SIZE (8U * 1024U * 1024U)
#define KSU_SEPOLICY_MAX_ARGS 5

struct sepol_data {
    u32 cmd;
    u32 subcmd;
};

struct sepol_batch_cursor {
    const u8 *cur;
    const u8 *end;
};

static size_t sepol_remaining(const struct sepol_batch_cursor *cursor)
{
    return (size_t)(cursor->end - cursor->cur);
}

static int sepol_read_cmd_header(struct sepol_batch_cursor *cursor, struct sepol_data *header)
{
    if (sepol_remaining(cursor) < sizeof(*header)) {
        return -EINVAL;
    }

    memcpy(header, cursor->cur, sizeof(*header));
    cursor->cur += sizeof(*header);

    return 0;
}

static int sepol_read_string(struct sepol_batch_cursor *cursor, const char **out)
{
    u32 len;
    const char *str;

    if (sepol_remaining(cursor) < sizeof(len)) {
        return -EINVAL;
    }

    memcpy(&len, cursor->cur, sizeof(len));
    cursor->cur += sizeof(len);

    if (len >= sepol_remaining(cursor)) {
        return -EINVAL;
    }

    str = (const char *)cursor->cur;
    if (memchr(str, '\0', len) != NULL || str[len] != '\0') {
        return -EINVAL;
    }

    cursor->cur += len + 1;
    if (len == 0) {
        *out = ALL;
        return 0;
    }

    *out = str;
    return 0;
}

static int sepol_require_not_all(const char *value, const char *name)
{
    if (value != ALL) {
        return 0;
    }

    pr_err("sepol: %s cannot be ALL.\n", name);
    return -EINVAL;
}

static int sepol_expected_argc(u32 cmd)
{
    switch (cmd) {
    case KSU_SEPOLICY_CMD_NORMAL_PERM:
        return 4;
    case KSU_SEPOLICY_CMD_XPERM:
        return 5;
    case KSU_SEPOLICY_CMD_TYPE_STATE:
        return 1;
    case KSU_SEPOLICY_CMD_TYPE:
    case KSU_SEPOLICY_CMD_TYPE_ATTR:
        return 2;
    case KSU_SEPOLICY_CMD_ATTR:
        return 1;
    case KSU_SEPOLICY_CMD_TYPE_TRANSITION:
        return 5;
    case KSU_SEPOLICY_CMD_TYPE_CHANGE:
        return 4;
    case KSU_SEPOLICY_CMD_GENFSCON:
        return 3;
    default:
        return -EINVAL;
    }
}

static int apply_one_sepolicy_cmd(struct policydb *db, const struct sepol_data *header, const char **args)
{
    bool success = false;
    int ret;

    switch (header->cmd) {
    case KSU_SEPOLICY_CMD_NORMAL_PERM:
        if (header->subcmd == KSU_SEPOLICY_SUBCMD_NORMAL_PERM_ALLOW) {
            success = ksu_allow(db, args[0], args[1], args[2], args[3]);
        } else if (header->subcmd == KSU_SEPOLICY_SUBCMD_NORMAL_PERM_DENY) {
            success = ksu_deny(db, args[0], args[1], args[2], args[3]);
        } else if (header->subcmd == KSU_SEPOLICY_SUBCMD_NORMAL_PERM_AUDITALLOW) {
            success = ksu_auditallow(db, args[0], args[1], args[2], args[3]);
        } else if (header->subcmd == KSU_SEPOLICY_SUBCMD_NORMAL_PERM_DONTAUDIT) {
            success = ksu_dontaudit(db, args[0], args[1], args[2], args[3]);
        } else {
            pr_err("sepol: unknown subcmd: %d\n", header->subcmd);
        }
        return success ? 0 : -EINVAL;

    case KSU_SEPOLICY_CMD_XPERM:
        ret = sepol_require_not_all(args[3], "operation");
        if (ret < 0) {
            return ret;
        }
        ret = sepol_require_not_all(args[4], "perm_set");
        if (ret < 0) {
            return ret;
        }

        if (header->subcmd == KSU_SEPOLICY_SUBCMD_XPERM_ALLOW) {
            success = ksu_allowxperm(db, args[0], args[1], args[2], args[4]);
        } else if (header->subcmd == KSU_SEPOLICY_SUBCMD_XPERM_AUDITALLOW) {
            success = ksu_auditallowxperm(db, args[0], args[1], args[2], args[4]);
        } else if (header->subcmd == KSU_SEPOLICY_SUBCMD_XPERM_DONTAUDIT) {
            success = ksu_dontauditxperm(db, args[0], args[1], args[2], args[4]);
        } else {
            pr_err("sepol: unknown subcmd: %d\n", header->subcmd);
        }
        return success ? 0 : -EINVAL;

    case KSU_SEPOLICY_CMD_TYPE_STATE:
        ret = sepol_require_not_all(args[0], "type");
        if (ret < 0) {
            return ret;
        }

        if (header->subcmd == KSU_SEPOLICY_SUBCMD_TYPE_STATE_PERMISSIVE) {
            success = ksu_permissive(db, args[0]);
        } else if (header->subcmd == KSU_SEPOLICY_SUBCMD_TYPE_STATE_ENFORCE) {
            success = ksu_enforce(db, args[0]);
        } else {
            pr_err("sepol: unknown subcmd: %d\n", header->subcmd);
        }
        return success ? 0 : -EINVAL;

    case KSU_SEPOLICY_CMD_TYPE:
    case KSU_SEPOLICY_CMD_TYPE_ATTR:
        ret = sepol_require_not_all(args[0], "type");
        if (ret < 0) {
            return ret;
        }
        ret = sepol_require_not_all(args[1], "attribute");
        if (ret < 0) {
            return ret;
        }

        if (header->cmd == KSU_SEPOLICY_CMD_TYPE) {
            success = ksu_type(db, args[0], args[1]);
        } else {
            success = ksu_typeattribute(db, args[0], args[1]);
        }
        if (!success) {
            pr_err("sepol: %d failed.\n", header->cmd);
            return -EINVAL;
        }
        return 0;

    case KSU_SEPOLICY_CMD_ATTR:
        ret = sepol_require_not_all(args[0], "attribute");
        if (ret < 0) {
            return ret;
        }

        if (!ksu_attribute(db, args[0])) {
            pr_err("sepol: %d failed.\n", header->cmd);
            return -EINVAL;
        }
        return 0;

    case KSU_SEPOLICY_CMD_TYPE_TRANSITION: {
        const char *object = ALL;

        ret = sepol_require_not_all(args[0], "src");
        if (ret < 0) {
            return ret;
        }
        ret = sepol_require_not_all(args[1], "tgt");
        if (ret < 0) {
            return ret;
        }
        ret = sepol_require_not_all(args[2], "cls");
        if (ret < 0) {
            return ret;
        }
        ret = sepol_require_not_all(args[3], "default_type");
        if (ret < 0) {
            return ret;
        }

        object = args[4];

        success = ksu_type_transition(db, args[0], args[1], args[2], args[3], object);
        return success ? 0 : -EINVAL;
    }

    case KSU_SEPOLICY_CMD_TYPE_CHANGE:
        ret = sepol_require_not_all(args[0], "src");
        if (ret < 0) {
            return ret;
        }
        ret = sepol_require_not_all(args[1], "tgt");
        if (ret < 0) {
            return ret;
        }
        ret = sepol_require_not_all(args[2], "cls");
        if (ret < 0) {
            return ret;
        }
        ret = sepol_require_not_all(args[3], "default_type");
        if (ret < 0) {
            return ret;
        }

        if (header->subcmd == KSU_SEPOLICY_SUBCMD_TYPE_CHANGE_CHANGE) {
            success = ksu_type_change(db, args[0], args[1], args[2], args[3]);
        } else if (header->subcmd == KSU_SEPOLICY_SUBCMD_TYPE_CHANGE_MEMBER) {
            success = ksu_type_member(db, args[0], args[1], args[2], args[3]);
        } else {
            pr_err("sepol: unknown subcmd: %d\n", header->subcmd);
        }
        return success ? 0 : -EINVAL;

    case KSU_SEPOLICY_CMD_GENFSCON:
        ret = sepol_require_not_all(args[0], "name");
        if (ret < 0) {
            return ret;
        }
        ret = sepol_require_not_all(args[1], "path");
        if (ret < 0) {
            return ret;
        }
        ret = sepol_require_not_all(args[2], "context");
        if (ret < 0) {
            return ret;
        }

        if (!ksu_genfscon(db, args[0], args[1], args[2])) {
            pr_err("sepol: %d failed.\n", header->cmd);
            return -EINVAL;
        }
        return 0;

    default:
        pr_err("sepol: unknown cmd: %d\n", header->cmd);
        return -EINVAL;
    }
}

static int ksu_parse_sepolicy_batch(struct policydb *db, u8 *payload, size_t data_len, int *success_cmd_count)
{
    struct sepol_batch_cursor cursor;
    int ret = 0;
    u32 cmd_index = 0;

    cursor.cur = payload;
    cursor.end = payload + data_len;
    *success_cmd_count = 0;

    while (cursor.cur < cursor.end) {
        struct sepol_data header;
        const char *args[KSU_SEPOLICY_MAX_ARGS] = { 0 };
        int expected_argc;
        u32 arg_index;

        ret = sepol_read_cmd_header(&cursor, &header);
        if (ret < 0) {
            pr_err("sepol: failed to read cmd header #%u.\n", cmd_index);
            return ret;
        }

        expected_argc = sepol_expected_argc(header.cmd);
        if (expected_argc < 0 || expected_argc > KSU_SEPOLICY_MAX_ARGS) {
            pr_err("sepol: invalid cmd header #%u.\n", cmd_index);
            return -EINVAL;
        }

        for (arg_index = 0; arg_index < (u32)expected_argc; arg_index++) {
            ret = sepol_read_string(&cursor, &args[arg_index]);
            if (ret < 0) {
                pr_err("sepol: failed to read cmd #%u arg #%u.\n", cmd_index, arg_index);
                return ret;
            }
        }

        ret = apply_one_sepolicy_cmd(db, &header, args);
        if (ret < 0) {
            pr_err("sepol: cmd #%u failed, cmd=%u subcmd=%u.\n", cmd_index, header.cmd, header.subcmd);
        } else {
            (*success_cmd_count)++;
        }
        cmd_index++;
    }

    return 0;
}

int handle_sepolicy(void __user *user_data, u64 data_len)
{
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0) || defined(KSU_COMPAT_HAS_POLICY_MUTEX)
    struct selinux_policy *pol, *old_pol;
#else
    struct policydb *policydb_ptr, *oldpolicydb, *newpolicydb;
    int len;
    u32 seqno;
#endif
    struct policydb *db;
    u8 *payload;
    int ret;
    int success_cmd_count = 0;

    if (!user_data || !data_len) {
        return -EINVAL;
    }

    if (data_len > KSU_SEPOLICY_MAX_BATCH_SIZE) {
        return -E2BIG;
    }

    payload = kvmalloc((size_t)data_len, GFP_KERNEL);
    if (!payload) {
        return -ENOMEM;
    }

    if (copy_from_user(payload, user_data, (size_t)data_len)) {
        ret = -EFAULT;
        goto out_free;
    }

    if (!getenforce()) {
        pr_info("SELinux permissive or disabled when handle policy!\n");
    }

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0) || defined(KSU_COMPAT_HAS_POLICY_MUTEX)
    mutex_lock(&selinux_state.policy_mutex);

    old_pol = rcu_dereference_protected(selinux_state.policy, lockdep_is_held(&selinux_state.policy_mutex));
    pol = ksu_dup_sepolicy(old_pol);
    if (IS_ERR(pol)) {
        ret = PTR_ERR(pol);
        pr_err("ksu_dup_sepolicy err: %d\n", ret);
        goto out_unlock;
    }
    db = &pol->policydb;

    ret = ksu_parse_sepolicy_batch(db, payload, data_len, &success_cmd_count);
    if (ret < 0)
        goto out_drop_new_policy;

    pol->latest_granting = old_pol->latest_granting + 1;
    if (!ksu_advance_original_types(db, &old_pol->policydb, old_pol->latest_granting, pol->latest_granting))
        pr_warn("failed to carry original type metadata, use backup lookups\n");

    rcu_assign_pointer(selinux_state.policy, pol);
    synchronize_rcu();
    ksu_destroy_sepolicy(old_pol);

    reset_avc_cache(pol->latest_granting);
    ret = success_cmd_count;
    goto out_unlock;

out_drop_new_policy:
    ksu_destroy_sepolicy(pol);
out_unlock:
    mutex_unlock(&selinux_state.policy_mutex);
#else
    policydb_ptr = get_policydb();
    oldpolicydb = kcalloc(2, sizeof(*oldpolicydb), GFP_KERNEL);
    if (!oldpolicydb) {
        ret = -ENOMEM;
        goto out_free;
    }
    newpolicydb = oldpolicydb + 1;
    db = newpolicydb;

    ksu_lock_sel_mutex_legacy();

retry:
#if defined(KSU_COMPAT_USE_SELINUX_STATE)
    seqno = selinux_state.ss->latest_granting + 1;
#else
    seqno = latest_granting_ptr ? (*latest_granting_ptr) + 1 : 1;
#endif

    len = ksu_dup_policydb(policydb_ptr, db);
    if (len < 0) {
        ret = len;
        goto out_free_locked;
    }

    ret = ksu_parse_sepolicy_batch(db, payload, data_len, &success_cmd_count);
    if (ret < 0)
        goto out_drop_new_policy;

    /* Save the old policydb to free later, then install the new one. */
    memcpy(oldpolicydb, policydb_ptr, sizeof(*policydb_ptr));

    ksu_lock_sepolicy_legacy();
#if defined(KSU_COMPAT_USE_SELINUX_STATE)
    if (selinux_state.ss->latest_granting + 1 != seqno) {
#else
    if (latest_granting_ptr && (*latest_granting_ptr) + 1 != seqno) {
#endif
        // sepolicy edited by someone else, retry
        ksu_unlock_sepolicy_legacy();
        ksu_destroy_policydb(newpolicydb);
        memset(newpolicydb, 0, sizeof(*newpolicydb));
        goto retry;
    }

    if (!ksu_advance_original_types(policydb_ptr, policydb_ptr, seqno - 1, seqno))
        pr_warn("failed to carry original type metadata, use backup lookups\n");

#if defined(KSU_COMPAT_USE_SELINUX_STATE)
    selinux_state.ss->latest_granting = seqno;
#else
    if (latest_granting_ptr)
        *latest_granting_ptr = seqno;
#endif
    memcpy(policydb_ptr, newpolicydb, sizeof(*policydb_ptr));
    ksu_unlock_sepolicy_legacy();

    reset_avc_cache(seqno);
    ksu_destroy_policydb(oldpolicydb);
    ret = success_cmd_count;
    goto out_free_locked;

out_drop_new_policy:
    ksu_destroy_policydb(newpolicydb);
out_free_locked:
    kfree(oldpolicydb);
    ksu_unlock_sel_mutex_legacy();
#endif
out_free:
    kvfree(payload);

    return ret;
}
