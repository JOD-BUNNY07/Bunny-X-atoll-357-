#ifndef __KSU_H_UTIL
#define __KSU_H_UTIL

/*
 * KazeSU's kernel-space helper header.
 *
 * The old-kernel compatibility helpers (ksyscall, userspace_stack_buffer,
 * ksu_filp_open_nonotify, ...) live in compat/kernel_compat.h so that they
 * stay in sync with tools/kernel_compat.mk.  This header is kept as the
 * stable include point for the rest of the tree.
 *
 * Adapted from BakaSU (https://github.com/Baka-SU/BakaSU).
 */
#include "compat/kernel_compat.h"

#endif // __KSU_H_UTIL
