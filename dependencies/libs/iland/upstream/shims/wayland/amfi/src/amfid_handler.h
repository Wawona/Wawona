#pragma once

int  install_hook(task_t task, mach_vm_address_t fn_addr);
void amfid_patch(void);
void amfid_unpatch(void);
