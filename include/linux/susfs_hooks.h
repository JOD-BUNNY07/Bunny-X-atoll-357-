#ifndef _FS_SUSFS_HOOKS_H
#define _FS_SUSFS_HOOKS_H

#include <linux/fs.h>
#include <linux/namei.h>
#include <linux/susfs.h>

/*
 * Susfs VFS hook layer - bridges VFS operations with Susfs subsystem
 * Backported from GKI 5.10 to 4.14 for Non-GKI kernels
 */

/* Path lookup hook - intercepts path resolution */
extern int susfs_hook_path_lookup(struct path *path, unsigned int flags);

/* Getattr hook - intercepts stat/fstat/lstat */
extern int susfs_hook_getattr(const struct path *path, struct kstat *stat,
			      u32 request_mask, unsigned int flags);

/* Exec hook - intercepts execve/execveat */
extern int susfs_hook_execve(struct filename *filename);

/* Setresuid hook - intercepts uid changes */
extern int susfs_hook_setresuid(uid_t ruid, uid_t euid, uid_t suid);

/* Faccessat hook - intercepts access checks */
extern int susfs_hook_faccessat(int dirfd, const char __user *pathname, int mode);

/* Read hook - intercepts read syscalls */
extern ssize_t susfs_hook_read(struct file *file, char __user *buf,
			       size_t count, loff_t *pos);

/* Reboot hook - intercepts reboot syscalls */
extern int susfs_hook_reboot(int cmd);

/* Input event hook - intercepts input events */
extern void susfs_hook_input_event(struct input_dev *dev,
				   unsigned int type, unsigned int code,
				   int value);

/* Initialize Susfs VFS hooks */
extern void susfs_vfs_hooks_init(void);

/* Cleanup Susfs VFS hooks */
extern void susfs_vfs_hooks_cleanup(void);

#endif /* _FS_SUSFS_HOOKS_H */
