#ifndef __KSU_H_SELINUX_DEFS
#define __KSU_H_SELINUX_DEFS

/*
 * Old-kernel SELinux state accessors.
 *
 * Adapted from BakaSU (https://github.com/Baka-SU/BakaSU),
 * kernel/selinux/selinux_defs.h.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

#include "selinux.h"
#include "objsec.h"
#include "security.h"
#ifndef KSU_COMPAT_USE_SELINUX_STATE
#include "avc.h"
#endif

#ifdef CONFIG_SECURITY_SELINUX_DISABLE
#ifdef KSU_COMPAT_USE_SELINUX_STATE
#define is_selinux_disabled() (selinux_state.disabled)
#else
/* selinux_disabled is private to hooks.c before 4.17 */
#define is_selinux_disabled() (0)
#endif
#else
#define is_selinux_disabled() (0)
#endif

#ifdef CONFIG_SECURITY_SELINUX_DEVELOP
#ifdef KSU_COMPAT_USE_SELINUX_STATE
#define __is_selinux_enforcing() (selinux_state.enforcing)
#define __setenforce(val) selinux_state.enforcing = (val)
#else
#define __is_selinux_enforcing() (selinux_enforcing)
#define __setenforce(val) selinux_enforcing = (val)
#endif
#else
#define __is_selinux_enforcing() (1)
#define __setenforce(val) ((void)(val))
#endif

#endif
