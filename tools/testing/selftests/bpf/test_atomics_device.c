// SPDX-License-Identifier: GPL-2.0
/* Standalone kernel verifier/JIT test; build with the Android NDK or Linux CC. */
#include <errno.h>
#include <linux/bpf.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef BPF_ATOMIC
#define BPF_ATOMIC 0xc0
#define BPF_FETCH 1
#define BPF_XCHG (0xe0 | BPF_FETCH)
#define BPF_CMPXCHG (0xf0 | BPF_FETCH)
#endif
#define I(c,d,s,o,v) ((struct bpf_insn){.code=(c),.dst_reg=(d),.src_reg=(s),.off=(o),.imm=(v)})
#define MOV(d,v) I(BPF_ALU64|BPF_MOV|BPF_K,d,0,0,v)
#define EXIT I(BPF_JMP|BPF_EXIT,0,0,0,0)
static char logbuf[65536];
static int load(struct bpf_insn *insns, unsigned n)
{
	union bpf_attr attr = {0};
	attr.prog_type = BPF_PROG_TYPE_SOCKET_FILTER;
	attr.insn_cnt = n;
	attr.insns = (uintptr_t)insns;
	attr.license = (uintptr_t)"GPL";
	attr.log_buf = (uintptr_t)logbuf;
	attr.log_size = sizeof(logbuf);
	attr.log_level = 1;
	logbuf[0] = 0;
	return syscall(__NR_bpf, BPF_PROG_LOAD, &attr, sizeof(attr));
}
static void run(unsigned op, int wide, int mismatch, int off)
{
	unsigned size = wide ? BPF_DW : BPF_W;
	unsigned expected = 42;
	unsigned simple = op & ~BPF_FETCH;
	if (simple == BPF_ADD) expected = 61;
	if (simple == BPF_AND) expected = 42 & 19;
	if (simple == BPF_OR) expected = 42 | 19;
	if (simple == BPF_XOR) expected = 42 ^ 19;
	if (op == BPF_XCHG || (op == BPF_CMPXCHG && !mismatch)) expected = 19;
	/* High halves in input/result catch missing u32 zero extension. */
	struct bpf_insn insns[] = {
		MOV(1, 1), I(BPF_ALU64|BPF_LSH|BPF_K,1,0,0,32),
		I(BPF_ALU64|BPF_ADD|BPF_K,1,0,0,42),
		I(BPF_STX|BPF_MEM|BPF_DW,10,1,-8,0),
		MOV(1, 19), MOV(0, mismatch ? 77 : 42),
		I(BPF_ALU64|BPF_MOV|BPF_X,2,10,0,0),
		I(BPF_ALU64|BPF_ADD|BPF_K,2,0,0,-8-off),
		I(BPF_STX|BPF_ATOMIC|size,2,1,off,op),
		/* Copy the returned value before using R0 for test status. */
		I(BPF_ALU64|BPF_MOV|BPF_X,3,op==BPF_CMPXCHG?0:1,0,0),
		I(BPF_LDX|BPF_MEM|size,4,10,-8,0),
		MOV(0, 1),
		I(BPF_JMP|BPF_JNE|BPF_K,4,0,3,expected),
		I(BPF_JMP|BPF_JNE|BPF_K,3,0,2,(op&BPF_FETCH)?42:19),
		MOV(0, 0), EXIT, EXIT,
	};
	/* For u64 cases use the same small value; u32 retains a poisoned upper half. */
	if (wide) insns[0] = MOV(1, 0);
	int fd = load(insns, sizeof(insns)/sizeof(insns[0]));
	if (fd < 0) {
		fprintf(stderr,"load failed op=%x size=%d off=%d: %s\n%s\n",op,wide?64:32,off,strerror(errno),logbuf);
		exit(1);
	}
	char data[64] = {0};
	union bpf_attr attr = {0};
	attr.test.prog_fd = fd;
	attr.test.data_in = (uintptr_t)data;
	attr.test.data_size_in = sizeof(data);
	attr.test.repeat = 1;
	if (syscall(__NR_bpf, BPF_PROG_TEST_RUN, &attr, sizeof(attr)) || attr.test.retval) {
		fprintf(stderr,"execution failed op=%x size=%d off=%d retval=%u: %s\n",op,wide?64:32,off,attr.test.retval,strerror(errno));
		exit(1);
	}
	close(fd);
}
int main(void)
{
	struct rlimit limit = {RLIM_INFINITY, RLIM_INFINITY};
	(void)setrlimit(RLIMIT_MEMLOCK, &limit);
	unsigned ops[] = {BPF_ADD,BPF_AND,BPF_OR,BPF_XOR,BPF_ADD|BPF_FETCH,
		BPF_AND|BPF_FETCH,BPF_OR|BPF_FETCH,BPF_XOR|BPF_FETCH,BPF_XCHG,BPF_CMPXCHG};
	unsigned count = 0;
	for (int wide=0; wide<2; wide++)
		for (unsigned i=0; i<sizeof(ops)/sizeof(ops[0]); i++)
			for (int mismatch=0; mismatch<2; mismatch++)
				for (int off=-8; off<=8; off+=8) {
					run(ops[i],wide,mismatch,off);
					count++;
				}
	/* Invalid operation and size must still be rejected, not silently executed. */
	for (int bad=0; bad<3; bad++) {
		struct bpf_insn insns[] = {
			MOV(1,1), I(BPF_ST|BPF_MEM|BPF_DW,10,0,-8,0),
			I(BPF_STX|BPF_ATOMIC|(bad==1?BPF_H:BPF_DW),10,1,-8,
			  bad==0?0x20:(BPF_ADD|BPF_FETCH)), MOV(0,0), EXIT,
		};
		if (bad==2) insns[2].src_reg=10; /* Fetch must not overwrite the frame pointer. */
		int fd=load(insns,sizeof(insns)/sizeof(insns[0]));
		if (fd>=0) { close(fd); fprintf(stderr,"invalid atomic accepted (%d)\n",bad); return 1; }
		if (errno!=EACCES && errno!=EINVAL) { perror("unexpected rejection"); return 1; }
	}
	printf("PASS: %u atomic execution cases and 3 verifier rejection cases\n",count);
	return 0;
}
