#import <Foundation/Foundation.h>
#include "amfid_handler.h"
#include <unistd.h>
#include <dlfcn.h>
#include <libproc.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <objc/runtime.h>
#include <ptrauth.h>
#include <stdio.h>
#include <string.h>

#define MFI_FRAMEWORK \
    "/System/Library/PrivateFrameworks/MobileFileIntegrity.framework/MobileFileIntegrity"

/* ── find amfid's PID ─────────────────────────────────────────────────── */

static pid_t
find_amfid_pid(void)
{
    int n = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0) / sizeof(pid_t);
    pid_t *pids = calloc(n, sizeof(pid_t));
    n = proc_listpids(PROC_ALL_PIDS, 0, pids, n * sizeof(pid_t)) / sizeof(pid_t);

    pid_t result = -1;
    for (int i = 0; i < n; i++) {
        char path[PROC_PIDPATHINFO_MAXSIZE];
        if (proc_pidpath(pids[i], path, sizeof(path)) > 0) {
            if (strcmp(path, "/usr/libexec/amfid") == 0) {
                result = pids[i];
                break;
            }
        }
    }
    free(pids);
    return result;
}

/* ── patch state (preserved for unpatch) ──────────────────────────────── */

#define MAX_HOOK_SIZE 16

static struct {
    task_t task;
    mach_vm_address_t fn_addr;
    mach_vm_address_t buf;
    uint8_t original[MAX_HOOK_SIZE];
    mach_vm_size_t hook_size;
    int active;
} g_patch;

/* ── install hook: let the original run, then force x0 = 1 ───────────── */
/*
 * Page layout (allocated in amfid):
 *
 *  [0x00]  trampoline
 *            [0x00..0x0F]  original 16 bytes saved from fn_addr
 *            [0x10..0x13]  LDR x17, #8        ; load fn_addr+16 from [0x18]
 *            [0x14..0x17]  BR  x17            ; jump into rest of original fn
 *            [0x18..0x1F]  <uint64: fn_addr + 16>
 *
 *  [0x20]  stub (this is what fn_addr's hook jumps to)
 *            [0x20..0x23]  STP x29, x30, [sp, #-16]!
 *            [0x24..0x27]  LDR x17, #20       ; load trampoline addr from [0x38]
 *            [0x28..0x2B]  BLR x17            ; call trampoline → original runs
 *            [0x2C..0x2F]  MOVZ x0, #1        ; override return value
 *            [0x30..0x33]  LDP x29, x30, [sp], #16
 *            [0x34..0x37]  RET
 *            [0x38..0x3F]  <uint64: trampoline addr>
 *
 *  Entry patch written at fn_addr (16 bytes):
 *            [0x00..0x03]  LDR x17, #8        ; load stub addr from [0x08]
 *            [0x04..0x07]  BR  x17
 *            [0x08..0x0F]  <uint64: stub addr>
 */

int
install_hook(task_t task, mach_vm_address_t fn_addr)
{
#if defined(__arm64__) || defined(__aarch64__)
    /*
     * arm64 layout (see comment block above install_hook):
     *   entry hook  : 16 bytes (LDR x17,#8 ; BR x17 ; <stub_addr>)
     *   trampoline  : saved 16 bytes + LDR x17,#8 + BR x17 + <fn+16>
     *   stub        : STP ; LDR x17,#20 ; BLR x17 ; MOVZ x0,#1 ; LDP ; RET ; <trampoline_addr>
     */
    const mach_vm_size_t hook_size = 16;

    uint8_t original[16];
    mach_vm_size_t read_size = hook_size;
    kern_return_t kr = mach_vm_read_overwrite(task, fn_addr, hook_size,
                                               (mach_vm_address_t)original, &read_size);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[amfid_handler] mach_vm_read_overwrite: %s\n", mach_error_string(kr));
        return -1;
    }

    mach_vm_address_t buf = 0;
    kr = mach_vm_allocate(task, &buf, PAGE_SIZE, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[amfid_handler] mach_vm_allocate: %s\n", mach_error_string(kr));
        return -1;
    }

    mach_vm_address_t trampoline_addr = buf + 0x00;
    mach_vm_address_t stub_addr       = buf + 0x20;
    uint64_t          continue_addr   = fn_addr + hook_size;

    uint8_t page_buf[PAGE_SIZE];
    memset(page_buf, 0, PAGE_SIZE);

    /* Trampoline */
    memcpy(page_buf + 0x00, original, hook_size);
    uint32_t ldr_x17_8  = 0x58000051u; /* LDR x17, #8  (imm19=2) */
    uint32_t br_x17     = 0xD61F0220u; /* BR  x17 */
    memcpy(page_buf + 0x10, &ldr_x17_8, 4);
    memcpy(page_buf + 0x14, &br_x17, 4);
    memcpy(page_buf + 0x18, &continue_addr, 8);

    /* Stub */
    uint32_t stp        = 0xA9BF7BFDu; /* STP x29, x30, [sp, #-16]! */
    uint32_t ldr_x17_20 = 0x580000B1u; /* LDR x17, #20 (imm19=5) */
    uint32_t blr_x17    = 0xD63F0220u; /* BLR x17 */
    uint32_t movz_x0_1  = 0xD2800020u; /* MOVZ x0, #1 */
    uint32_t ldp        = 0xA8C17BFDu; /* LDP x29, x30, [sp], #16 */
    uint32_t ret_insn   = 0xD65F03C0u; /* RET */
    memcpy(page_buf + 0x20, &stp, 4);
    memcpy(page_buf + 0x24, &ldr_x17_20, 4);
    memcpy(page_buf + 0x28, &blr_x17, 4);
    memcpy(page_buf + 0x2C, &movz_x0_1, 4);
    memcpy(page_buf + 0x30, &ldp, 4);
    memcpy(page_buf + 0x34, &ret_insn, 4);
    memcpy(page_buf + 0x38, &trampoline_addr, 8);

    /* Entry hook: LDR x17, #8 ; BR x17 ; <stub_addr> */
    uint8_t entry_hook[16];
    uint32_t ldr_hook = 0x58000051u;
    uint32_t br_hook  = 0xD61F0220u;
    memcpy(entry_hook + 0, &ldr_hook, 4);
    memcpy(entry_hook + 4, &br_hook, 4);
    memcpy(entry_hook + 8, &stub_addr, 8);

#elif defined(__x86_64__)
    /*
     * x86_64 layout:
     *   entry hook  : 14 bytes (FF 25 00 00 00 00 ; <stub_addr uint64>)
     *                 JMP [RIP+0] — reads stub_addr from the 8 bytes immediately after
     *
     *   trampoline  : saved 14 bytes
     *               + FF 25 00 00 00 00 ; <fn_addr+14 uint64>
     *                 JMP [RIP+0] — continues into the rest of the original fn
     *
     *   stub        : 55                   PUSH RBP
     *               + 48 89 E5             MOV  RBP, RSP
     *               + FF 15 0E 00 00 00    CALL [RIP+14]  → trampoline_addr at [0x38]
     *               + B8 01 00 00 00       MOV  EAX, 1
     *               + 5D                  POP  RBP
     *               + C3                  RET
     *               + (pad to 0x38)
     *               + <trampoline_addr uint64>
     */
    const mach_vm_size_t hook_size = 14;

    uint8_t original[14];
    mach_vm_size_t read_size = hook_size;
    kern_return_t kr = mach_vm_read_overwrite(task, fn_addr, hook_size,
                                               (mach_vm_address_t)original, &read_size);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[amfid_handler] mach_vm_read_overwrite: %s\n", mach_error_string(kr));
        return -1;
    }

    mach_vm_address_t buf = 0;
    kr = mach_vm_allocate(task, &buf, PAGE_SIZE, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[amfid_handler] mach_vm_allocate: %s\n", mach_error_string(kr));
        return -1;
    }

    mach_vm_address_t trampoline_addr = buf + 0x00;
    mach_vm_address_t stub_addr       = buf + 0x20;
    uint64_t          continue_addr   = fn_addr + hook_size;

    uint8_t page_buf[PAGE_SIZE];
    memset(page_buf, 0, PAGE_SIZE);

    /* Trampoline: original bytes + JMP [RIP+0] + <fn_addr+14> */
    memcpy(page_buf + 0x00, original, hook_size);          /* 0x00..0x0D */
    page_buf[0x0E] = 0xFF; page_buf[0x0F] = 0x25;          /* JMP [RIP+0] */
    page_buf[0x10] = 0x00; page_buf[0x11] = 0x00;
    page_buf[0x12] = 0x00; page_buf[0x13] = 0x00;
    memcpy(page_buf + 0x14, &continue_addr, 8);            /* 0x14..0x1B */

    /* Stub at 0x20:
     *   0x20: 55                  PUSH RBP
     *   0x21: 48 89 E5            MOV  RBP, RSP
     *   0x24: FF 15 0E 00 00 00   CALL [RIP+14]  (→ reads from 0x2A+14 = 0x38)
     *   0x2A: B8 01 00 00 00      MOV  EAX, 1
     *   0x2F: 5D                  POP  RBP
     *   0x30: C3                  RET
     *   0x38: <trampoline_addr>
     */
    page_buf[0x20] = 0x55;
    page_buf[0x21] = 0x48; page_buf[0x22] = 0x89; page_buf[0x23] = 0xE5;
    page_buf[0x24] = 0xFF; page_buf[0x25] = 0x15;
    page_buf[0x26] = 0x0E; page_buf[0x27] = 0x00; /* imm32 = 14 */
    page_buf[0x28] = 0x00; page_buf[0x29] = 0x00;
    page_buf[0x2A] = 0xB8; page_buf[0x2B] = 0x01; /* MOV EAX, 1 */
    page_buf[0x2C] = 0x00; page_buf[0x2D] = 0x00; page_buf[0x2E] = 0x00;
    page_buf[0x2F] = 0x5D;                          /* POP RBP */
    page_buf[0x30] = 0xC3;                          /* RET */
    memcpy(page_buf + 0x38, &trampoline_addr, 8);

    /* Entry hook: JMP [RIP+0] + <stub_addr> */
    uint8_t entry_hook[14];
    entry_hook[0] = 0xFF; entry_hook[1] = 0x25;
    entry_hook[2] = 0x00; entry_hook[3] = 0x00;
    entry_hook[4] = 0x00; entry_hook[5] = 0x00;
    memcpy(entry_hook + 6, &stub_addr, 8);

#else
#error "unsupported architecture"
#endif

    /* Write page to amfid and make it executable */
    kr = mach_vm_write(task, buf, (vm_offset_t)page_buf, PAGE_SIZE);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[amfid_handler] mach_vm_write (page): %s\n", mach_error_string(kr));
        mach_vm_deallocate(task, buf, PAGE_SIZE);
        return -1;
    }
    kr = mach_vm_protect(task, buf, PAGE_SIZE, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[amfid_handler] mach_vm_protect (page rx): %s\n", mach_error_string(kr));
        mach_vm_deallocate(task, buf, PAGE_SIZE);
        return -1;
    }

    /* Patch fn_addr with the entry hook (COW for shared cache pages) */
    mach_vm_address_t page = fn_addr & ~((mach_vm_address_t)PAGE_SIZE - 1);
    kr = mach_vm_protect(task, page, PAGE_SIZE, FALSE,
                         VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[amfid_handler] mach_vm_protect (fn rw): %s\n", mach_error_string(kr));
        mach_vm_deallocate(task, buf, PAGE_SIZE);
        return -1;
    }
    kr = mach_vm_write(task, fn_addr, (vm_offset_t)entry_hook, hook_size);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[amfid_handler] mach_vm_write (hook): %s\n", mach_error_string(kr));
        mach_vm_protect(task, page, PAGE_SIZE, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
        mach_vm_deallocate(task, buf, PAGE_SIZE);
        return -1;
    }
    kr = mach_vm_protect(task, page, PAGE_SIZE, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS)
        fprintf(stderr, "[amfid_handler] mach_vm_protect (fn rx): %s\n", mach_error_string(kr));

    printf("[amfid_handler] stub @ 0x%llx  trampoline @ 0x%llx\n",
           (unsigned long long)stub_addr, (unsigned long long)trampoline_addr);

    g_patch.fn_addr = fn_addr;
    g_patch.buf = buf;
    g_patch.hook_size = hook_size;
    memcpy(g_patch.original, original, hook_size);
    return 0;
}

/* ── public: patch -[AMFIPathValidator_macos validateWithError:] ─────── */

void
amfid_patch(void)
{
    pid_t pid;
FindAMFI:
    pid = find_amfid_pid();
    if (pid < 0) {
        fprintf(stderr, "[amfid_handler] amfid not found, trying again in a few\n");
        usleep(1666);
        goto FindAMFI;
        return;
    }

    if (!dlopen(MFI_FRAMEWORK, RTLD_NOW | RTLD_NOLOAD))
        dlopen(MFI_FRAMEWORK, RTLD_NOW);

    Class cls = objc_getClass("AMFIPathValidator_macos");
    if (!cls) {
        fprintf(stderr, "[amfid_handler] AMFIPathValidator_macos not found\n");
        return;
    }

    Method m = class_getInstanceMethod(cls, sel_registerName("validateWithError:"));
    if (!m) {
        fprintf(stderr, "[amfid_handler] validateWithError: not found\n");
        return;
    }

    IMP imp = method_getImplementation(m);
#if __has_feature(ptrauth_calls)
    imp = ptrauth_strip(imp, ptrauth_key_function_pointer);
#endif
    mach_vm_address_t fn_addr = (mach_vm_address_t)(uintptr_t)imp;
    printf("[amfid_handler] IMP @ 0x%llx\n", (unsigned long long)fn_addr);

    task_t task = MACH_PORT_NULL;
    kern_return_t kr = task_for_pid(mach_task_self(), (int)pid, &task);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[amfid_handler] task_for_pid(%d): %s\n", pid, mach_error_string(kr));
        return;
    }

    g_patch.task = task;
    if (install_hook(task, fn_addr) == 0) {
        g_patch.active = 1;
        printf("[amfid_handler] hooked amfid (pid %d)\n", pid);
    } else {
        g_patch.active = 0;
        mach_port_deallocate(mach_task_self(), task);
    }
}

void
amfid_unpatch(void)
{
    if (!g_patch.active) return;

    mach_vm_address_t page = g_patch.fn_addr & ~((mach_vm_address_t)PAGE_SIZE - 1);
    kern_return_t kr;

    kr = mach_vm_protect(g_patch.task, page, PAGE_SIZE, FALSE,
                         VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr == KERN_SUCCESS) {
        kr = mach_vm_write(g_patch.task, g_patch.fn_addr,
                           (vm_offset_t)g_patch.original, g_patch.hook_size);
        if (kr == KERN_SUCCESS) {
            mach_vm_protect(g_patch.task, page, PAGE_SIZE, FALSE,
                            VM_PROT_READ | VM_PROT_EXECUTE);
            printf("[amfid_handler] restored original bytes at 0x%llx\n",
                   (unsigned long long)g_patch.fn_addr);
        }
    }

    mach_vm_deallocate(g_patch.task, g_patch.buf, PAGE_SIZE);
    mach_port_deallocate(mach_task_self(), g_patch.task);
    memset(&g_patch, 0, sizeof(g_patch));
}

/* ── entry point ─────────────────────────────────────────────────────── */

int
main(void)
{
    @autoreleasepool {
        amfid_patch();
    }
    return 0;
}
