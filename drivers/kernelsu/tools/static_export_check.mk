# Static symbol export checks for manual-hook trees without KALLSYMS_ALL.
#
# Adapted from BakaSU (https://github.com/Baka-SU/BakaSU),
# kernel/tools/static_export_check.mk.
define check_symbol_export
  $(eval _ARG1 := $(strip $(1)))
  $(eval _ARG2 := $(strip $(2)))
  $(eval _ARG3 := $(strip $(3)))
  $(eval _ARG4 := $(strip $(4)))

  ifneq ($$(shell grep -q -F "$$(_ARG1)" $$(_ARG2); echo $$$$?),0)
      $$(info -- $$(REPO_NAME)/symbol_export: export $$(_ARG3) found)
  else
      $$(info -- You disabled CONFIG_KALLSYMS_ALL and haven't export $$(_ARG3) in your kernel's $$(notdir $$(_ARG2)) file)
      $$(info -- Read: docs/old-kernels.md#symbol-exports)
      $$(error You should integrate $$(REPO_NAME) in your kernel. $$(_ARG4))
  endif
endef

# feature/selinux_hide.c is only compiled when the post-5.7 policy container
# is present; keep its symbol requirements off older trees.
KSU_HIDE_SUPPORTED := $(shell grep -q "policy_mutex" $(srctree)/security/selinux/include/security.h && echo y)
# Pre-4.17 kernels expose the policy state through globals instead of
# struct selinux_state.
KSU_HAS_SELINUX_STATE := $(shell grep -q "struct selinux_state " $(srctree)/security/selinux/include/security.h && echo y)

ifeq ($(KSU_HIDE_SUPPORTED),y)
# Reason: selinux_hide
$(eval $(call check_symbol_export, static ssize_t (*write_op[]), $(srctree)/security/selinux/selinuxfs.c, write_op))

# Reason: selinux_hide
$(eval $(call check_symbol_export, static const struct file_operations sel_handle_status_ops, $(srctree)/security/selinux/selinuxfs.c, sel_handle_status_ops))

# Reason: selinux_hide
$(eval $(call check_symbol_export, static void security_dump_masked_av, $(srctree)/security/selinux/ss/services.c, security_dump_masked_av func))

# Reason: selinux_hide
$(eval $(call check_symbol_export, static void context_struct_compute_av, $(srctree)/security/selinux/ss/services.c, context_struct_compute_av func))
endif

# Pre-4.17: the policy globals must be reachable without KALLSYMS_ALL.
ifneq ($(KSU_HAS_SELINUX_STATE),y)
# Reason: safe policydb patch/dup
$(eval $(call check_symbol_export, static DEFINE_MUTEX(sel_mutex), $(srctree)/security/selinux/selinuxfs.c, sel_mutex))
$(eval $(call check_symbol_export, static DEFINE_RWLOCK(policy_rwlock), $(srctree)/security/selinux/ss/services.c, policy_rwlock))
$(eval $(call check_symbol_export, static u32 latest_granting, $(srctree)/security/selinux/ss/services.c, latest_granting))
endif

# if kernel < 4.2, we should check selinux_ops has NOT been static.
ifeq ($(shell test $(VERSION) -lt 4 -o \( $(VERSION) -eq 4 -a $(PATCHLEVEL) -lt 2 \) && echo y),y)
    # Reason: We need LSM hooks
    $(eval $(call check_symbol_export, static struct security_operations selinux_ops, $(srctree)/security/selinux/hooks.c, selinux_ops))
endif
