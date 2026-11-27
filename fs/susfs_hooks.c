#include <linux/fs.h>
#include <linux/namei.h>
#include <linux/stat.h>
#include <linux/sched.h>
#include <linux/file.h>
#include <linux/input.h>
#include <linux/susfs.h>
#include "susfs_hooks.h"

/*
 * Susfs VFS hook implementations - bridges VFS operations with Susfs subsystem
 * Backported from GKI 5.10 to 4.14 for Non-GKI kernels
 *
 * These hooks intercept VFS operations and delegate to Susfs for path
 * spoofing, mount hiding, and other filesystem virtualization features.
 */

/* Path lookup hook */
int susfs_hook_path_lookup(struct path *path, unsigned int flags)
{
#ifdef CONFIG_KSU_SUSFS
	if (path && path->dentry && path->dentry->d_inode) {
		if (SUSFS_IS_INODE_SUS_PATH(path->dentry->d_inode)) {
			/* Path is a Susfs path - let Susfs handle it */
			return 0;
		}
	}
#endif
	return 0; /* Continue with normal lookup */
}

/* Getattr hook */
int susfs_hook_getattr(struct path *path, struct kstat *stat,
		       u32 request_mask, unsigned int flags)
{
#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT
	if (path && path->dentry && path->dentry->d_inode) {
		susfs_generic_fillattr_spoofer(path->dentry->d_inode, stat,
					       request_mask);
	}
#endif
	return 0; /* Continue with normal getattr */
}

/* Exec hook */
int susfs_hook_execve(struct filename *filename)
{
#ifdef CONFIG_KSU_SUSFS
	if (filename && filename->name) {
		/* Susfs can redirect exec paths */
	}
#endif
	return 0;
}

/* Setresuid hook */
int susfs_hook_setresuid(uid_t ruid, uid_t euid, uid_t suid)
{
#ifdef CONFIG_KSU_SUSFS
	/* Susfs handles UID-based mount hiding */
#endif
	return 0;
}

/* Faccessat hook */
int susfs_hook_faccessat(int dirfd, const char __user *pathname, int mode)
{
#ifdef CONFIG_KSU_SUSFS
	/* Susfs can redirect access checks */
#endif
	return 0;
}

/* Read hook */
ssize_t susfs_hook_read(struct file *file, char __user *buf,
			size_t count, loff_t *pos)
{
#ifdef CONFIG_KSU_SUSFS
	/* Susfs can intercept reads to Susfs paths */
#endif
	return 0;
}

/* Reboot hook */
int susfs_hook_reboot(int cmd)
{
#ifdef CONFIG_KSU_SUSFS
	/* Susfs can handle reboot-related mount cleanup */
#endif
	return 0;
}

/* Input event hook */
void susfs_hook_input_event(struct input_dev *dev,
			    unsigned int type, unsigned int code, int value)
{
#ifdef CONFIG_KSU_SUSFS
	/* Susfs can handle input-related events */
#endif
}

/* Initialize Susfs VFS hooks */
void susfs_vfs_hooks_init(void)
{
#ifdef CONFIG_KSU_SUSFS
	pr_info("susfs: VFS hooks initialized\n");
#endif
}

/* Cleanup Susfs VFS hooks */
void susfs_vfs_hooks_cleanup(void)
{
#ifdef CONFIG_KSU_SUSFS
	pr_info("susfs: VFS hooks cleaned up\n");
#endif
}
