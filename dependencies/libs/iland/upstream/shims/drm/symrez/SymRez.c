//
//  SymRez.c
//  SymRez
//
//  Created by Jeremy Legendre on 4/14/20.
//  Copyright © 2020 Jeremy Legendre. All rights reserved.
//

#include <SymRez/SymRez.h>
#include <stdlib.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <mach-o/nlist.h>
#include <mach/mach_vm.h>

#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif

#ifndef EXPORT_SYMBOL_FLAGS_WEAK_REEXPORT
#define EXPORT_SYMBOL_FLAGS_WEAK_REEXPORT 0xC
#endif

#ifndef SR_STATIC
  #if defined(DEBUG)
    #define SR_STATIC
  #else
    #define SR_STATIC static
  #endif
#endif

#define ALIGN_64 __attribute__((__aligned__(64)))

#ifndef SR_ITER_STACK_DEPTH
#define SR_ITER_STACK_DEPTH 0x48
#endif

#define likely(x)   __builtin_expect(!!(x), 1)
#define unlikely(x) __builtin_expect(!!(x), 0)

#define _strlen strlen
#undef strlen
#define strlen(x) \
__builtin_constant_p(x) ? sizeof(x) : _strlen(x)

#define sr_strneq(x,y,z) \
!strncmp(x,y,z)

#define mh_for_each_lc(mh, lc) \
for (struct load_command *lc = (struct load_command*)((uint64_t)mh + sizeof(struct mach_header_64)); \
    (uint64_t)lc < (((uint64_t)mh + sizeof(struct mach_header_64)) + mh->sizeofcmds); \
    lc = (void*)((uint64_t)lc + (uint64_t)lc->cmdsize))

#define _sr_for_each_image_info(it, info) \
dyld_all_image_infos_t info = get_all_image_infos(); \
for(const struct dyld_image_info *it = info->infoArray; \
    it < &info->infoArray[info->infoArrayCount]; \
    ++it)

#define sr_for_each_image_info(it) \
    _sr_for_each_image_info(it, aii##__COUNTER__)

extern const struct mach_header_64 _mh_execute_header;
typedef struct load_command* load_command_t;
typedef struct segment_command_64* segment_command_t;
typedef struct section_64* section_t;
typedef struct dyld_all_image_infos* dyld_all_image_infos_t;
typedef struct nlist_64* nlist64_t;
typedef void* strtab_t;

SR_STATIC bool symrez_init_mh(symrez_t symrez, mach_header_t mach_header);

struct ALIGN_64 symrez {
    mach_header_t header;
    intptr_t slide;
    nlist64_t symtab;
    strtab_t strtab;
    uint32_t nsyms;
    void *exports;
    uintptr_t exports_size;
    sr_iterator_t iterator;
};

struct sr_iter_result {
    sr_ptr_t ptr;
    sr_symbol_t symbol;
};

typedef struct ALIGN_64 
sr_symtab_iterator {
    nlist64_t start;
    nlist64_t end;
    nlist64_t curr;
} *sr_symtab_iter_t;

// Should node_stack be a dynamic array?
typedef struct ALIGN_64 
sr_export_iterator {
    void *start;
    int32_t stack_top;
    struct stack_node {
        const uint8_t* node;
        char sym[2048];
        size_t sym_len;
    } node_stack[SR_ITER_STACK_DEPTH];
} *sr_export_iter_t;

struct ALIGN_64 sr_iterator {
    symrez_t symrez;
    struct sr_symtab_iterator symtab_iter;
    struct sr_export_iterator export_iter;
    struct sr_iter_result result;
};


SR_INLINE const char * _Nullable
sr_strrchr(const char *s, int c) {
    size_t len = strlen(s) - 1;
    const char *pp = (s + len);
    while (len-- >= 0) {
        if (unlikely(*pp-- == c)) {
            return pp+2;
        }
    }
    
    return NULL;
}

SR_INLINE uint64_t
read_uleb128(void** ptr) {
    uint8_t *p = *ptr;
    uint64_t result = 0;
    int bit = 0;
    
    do {
        uint64_t slice = *p & 0x7f;
        result |= (slice << bit);
        bit += 7;
    } while (*p++ & 0x80);
    
    *ptr = p;
    return result;
}

SR_STATIC const uint8_t* 
walk_export_trie(const uint8_t* start, const uint8_t* end, const char* symbol) {
    const uint8_t* p = start;
    while (unlikely(p < end)) {
        uintptr_t terminal_size = *p++;
        
        if (unlikely(terminal_size > 127)) {
            --p;
            terminal_size = read_uleb128((void**)&p);
        }
        
        if (unlikely((*symbol == '\0') && (terminal_size != 0))) {
            return p;
        }
        
        const uint8_t* children = p + terminal_size;
        if (unlikely(children > end)) {
            return NULL;
        }

        uint8_t childrenRemaining = *children++;
        p = children;
        uintptr_t node_offset = 0;
        
        for (; childrenRemaining > 0; --childrenRemaining) {
            const char* ss = symbol;
            bool wrong_edge = false;
            
            while (likely(*p != '\0')) {
                if (!wrong_edge) {
                    if (*p != *ss++) {
                        wrong_edge = true;
                    }
                }
                ++p;
            }
            ++p;
            
            if (likely(wrong_edge)) {
                node_offset = 0;
                while ((*p++ & 0x80) != 0) {}
            } else {
                node_offset = read_uleb128((void**)&p);
                p = &start[node_offset];
                symbol = ss;
                break;
            }
        }
        
        if (unlikely(!node_offset)) break;
    }
    return NULL;
}

SR_STATIC OS_NOINLINE
dyld_all_image_infos_t _get_dyld_info(void) {
    task_dyld_info_data_t dyld_info;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kern_return_t kr = task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)&dyld_info, &count);
    if (unlikely(kr != KERN_SUCCESS)) {
        return NULL;
    }
    
    return (dyld_all_image_infos_t)(dyld_info.all_image_info_addr);
}

SR_STATIC OS_PURE
dyld_all_image_infos_t get_all_image_infos(void) {
    static dyld_all_image_infos_t _g_all_image_infos = NULL;
    if (unlikely(!_g_all_image_infos)) {
        _g_all_image_infos = _get_dyld_info();
    } else {
        __asm__ __volatile__("" ::: "memory");
    }
    
    __builtin_assume(_g_all_image_infos != NULL);
    return _g_all_image_infos;
}

SR_INLINE OS_OVERLOADABLE segment_command_t
find_lc_segment(mach_header_t mh, const char *segname, size_t len) {
    mh_for_each_lc(mh, lc) {
        if (lc->cmd == LC_SEGMENT_64) {
            segment_command_t seg = (segment_command_t)lc;
            if (sr_strneq(seg->segname, segname, len)) {
                return seg;
            }
        }
    }
    
    return NULL;
}

SR_INLINE segment_command_t
find_lc_segment(mach_header_t mh, const char *segname) {
    return find_lc_segment(mh, segname, strlen(segname));
}

SR_INLINE load_command_t
find_load_command(mach_header_t mh, uint32_t cmd) {
    mh_for_each_lc(mh, lc) {
        if (lc->cmd == cmd) {
            return lc;
        }
    }
    
    return NULL;
}

SR_STATIC const char *
dylib_name_for_ordinal(mach_header_t mh, uintptr_t ordinal) {
    mh_for_each_lc(mh, lc) {
        switch (lc->cmd) {
            case LC_LOAD_DYLIB:
            case LC_LOAD_WEAK_DYLIB:
            case LC_REEXPORT_DYLIB:
            case LC_LOAD_UPWARD_DYLIB: {
                if (--ordinal == 0) {
                    const struct dylib_command *dylibCmd = (void*)lc;
                    return (const char*)((void*)dylibCmd + dylibCmd->dylib.name.offset);;
                }
            }
        }
    }

    __builtin_unreachable();
}

SR_INLINE intptr_t
compute_image_slide(mach_header_t mh) {
    intptr_t res = 0;
    uint64_t mh_addr = (uint64_t)(void*)mh;
    segment_command_t seg = find_lc_segment(mh, SEG_TEXT);
    res = mh_addr - (seg->vmaddr);
    return res;
}

SR_STATIC int find_linkedit_commands(symrez_t symrez) {
    mach_header_t mh = symrez->header;
    intptr_t slide = symrez->slide;
    
    segment_command_t linkedit = find_lc_segment(mh, SEG_LINKEDIT);
    if (unlikely(!linkedit)) {
        return 0;
    }
    
    struct symtab_command *symtab = (void*)find_load_command(mh, LC_SYMTAB);
    if (unlikely(!symtab)) {
        return 0;
    }
    
    symrez->nsyms = symtab->nsyms;
    symrez->strtab = (strtab_t)((linkedit->vmaddr - linkedit->fileoff) + symtab->stroff + slide);
    symrez->symtab = (nlist64_t)((linkedit->vmaddr - linkedit->fileoff) + symtab->symoff + slide);
    
    struct linkedit_data_command *exportInfo = (struct linkedit_data_command *)find_load_command(mh, LC_DYLD_EXPORTS_TRIE);
    if (likely(exportInfo)) {
        symrez->exports = (void*)(linkedit->vmaddr - linkedit->fileoff) + exportInfo->dataoff + symrez->slide;
        symrez->exports_size = exportInfo->datasize;
        return 1;
    }
    
    struct dyld_info_command *dyld_info = (void*)find_load_command(mh, LC_DYLD_INFO_ONLY);
    if (unlikely(!dyld_info)) {
        dyld_info = (void*)find_load_command(mh, LC_DYLD_INFO);
    }
    
    if (unlikely(dyld_info)) {
        symrez->exports = (void*)(linkedit->vmaddr - linkedit->fileoff) + dyld_info->export_off + symrez->slide;
        symrez->exports_size = dyld_info->export_size;
    }
    
    return 1;
}

SR_INLINE mach_header_t
find_image_by_name(const char *image_name, size_t len) {
    uint32_t block = *(uint32_t*)image_name;
    sr_for_each_image_info(info) {
        const char *p = info->imageFilePath;
        const char *img = sr_strrchr(p, '/');

        if (block ^ *(uint32_t*)img) continue;
        if (sr_strneq(img, image_name, len)) {
            return (mach_header_t)(info->imageLoadAddress);
        }
    }
    
    return NULL;
}

SR_STATIC mach_header_t
find_image(const char *image_name) {
    size_t name_len = strlen(image_name);
    
    if (*image_name ^ '/') {
        return find_image_by_name(image_name, name_len);
    }

    sr_for_each_image_info(info) {
        const char *p = info->imageFilePath;
        if (unlikely(sr_strneq(p, image_name, name_len))) {
            return (mach_header_t)(info->imageLoadAddress);
        }
    }

    return NULL;
}

SR_STATIC mach_header_t
get_base_addr(void) {
    dyld_all_image_infos_t dyld_all_image_infos = get_all_image_infos();
    if (likely(dyld_all_image_infos)) {
        return (mach_header_t)(dyld_all_image_infos->infoArray[0].imageLoadAddress);
    }
    
    // Fallback
    kern_return_t kr = KERN_FAILURE;
    vm_region_basic_info_data_t info = { 0 };
    mach_vm_size_t size = 0;
    mach_port_t object_name = MACH_PORT_NULL;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_vm_address_t address = 0x100000000;
    
    while (kr != KERN_SUCCESS) {
        address += size;
        kr = mach_vm_region(current_task(), &address, &size, VM_REGION_BASIC_INFO, (vm_region_info_t) &info, &count, &object_name);
    }
    
    return (mach_header_t)address;
}

SR_INLINE void *
resolve_export_node(const uint8_t *node, mach_header_t mh, const char *symbol) {
    void *addr = NULL;
    uintptr_t flags = read_uleb128((void**)&node);
    if (unlikely(flags & EXPORT_SYMBOL_FLAGS_REEXPORT)) {
        uintptr_t ordinal = read_uleb128((void**)&node);
        const char* importedName = (const char*)node;
        if (!importedName || importedName[0] == '\0') {
            importedName = symbol;
        }

        const char *dylib = dylib_name_for_ordinal(mh, ordinal);
        
        if (unlikely(!dylib)) return NULL;
        
        struct symrez sr;
        mach_header_t hdr = NULL;
        if (unlikely(!(hdr = find_image(dylib)))) return NULL;
        if (unlikely(!symrez_init_mh(&sr, hdr))) return NULL;
        
        return sr_resolve_symbol(&sr, importedName);
    }

    switch (flags & EXPORT_SYMBOL_FLAGS_KIND_MASK) {
        case EXPORT_SYMBOL_FLAGS_KIND_REGULAR: {
            uint64_t offset = read_uleb128((void**)&node);
            addr = (void*)(offset + (uint64_t)mh);
            break;
        }
        case EXPORT_SYMBOL_FLAGS_KIND_ABSOLUTE:
            addr = (void*)read_uleb128((void**)&node);
            break;
        default:
            break;
    }
    
    return addr;
}

SR_INLINE void
_sr_iter_init_from_sr(sr_iterator_t iterator, symrez_t symrez) {
    iterator->symrez = symrez;
    iterator->result.ptr = NULL;
    iterator->result.symbol = NULL;
    
    nlist64_t symtab = symrez->symtab;
    void *exports = symrez->exports;
    
    if (likely(symtab)) {
        iterator->symtab_iter.start = symtab;
        iterator->symtab_iter.curr = symtab;
        iterator->symtab_iter.end = &symtab[symrez->nsyms];
    }
    
    
    if (likely(exports)) {
        iterator->export_iter.start = exports;
        iterator->export_iter.stack_top = 1;
        iterator->export_iter.node_stack[0].node = exports;
        iterator->export_iter.node_stack[0].sym_len = 0;
    }
}

sr_iterator_t sr_iterator_create(symrez_t symrez) {
    sr_iterator_t iterator = calloc(1, sizeof(struct sr_iterator));
    _sr_iter_init_from_sr(iterator, symrez);
    return iterator;
}

void sr_iter_reset(sr_iterator_t iterator) {
    symrez_t symrez = iterator->symrez;
    iterator->symtab_iter.curr = symrez->symtab;
    
    void *exports = symrez->exports;
    if (likely(exports)) {
        iterator->export_iter.stack_top = 1;
        iterator->export_iter.node_stack[0].node = exports;
        iterator->export_iter.node_stack[0].sym_len = 0;
    }
}

sr_ptr_t sr_iter_get_ptr(sr_iterator_t iter) {
    return iter->result.ptr;
}

sr_symbol_t sr_iter_get_symbol(sr_iterator_t iter) {
    return iter->result.symbol;
}

size_t sr_iter_copy_symbol(sr_iterator_t iter, char *dest) {
    if (!iter->result.symbol) return 0;
    size_t ret = strlen(iter->result.symbol);
    
    if (dest) {
        strncpy(dest, iter->result.symbol, ret);
    }
    
    return ret;
}

SR_INLINE sr_iter_result_t
sr_iter_get_next_nlist(sr_iterator_t iter) {
    sr_symtab_iter_t it = &iter->symtab_iter;
    symrez_t sr = iter->symrez;
    strtab_t strtab = sr->strtab;
    intptr_t slide = sr->slide;
    
    for (nlist64_t nl = it->curr; nl < it->end; ++nl) {
        if (nl->n_un.n_strx == 0) continue;
        if ((nl->n_type & N_STAB) || nl->n_sect == 0 || ((nl->n_type & N_EXT) && sr->exports)) {
            continue;
        }

        char *str = (char *)strtab + nl->n_un.n_strx;
        it->curr = ++nl;
        iter->result.symbol = str;
        iter->result.ptr = (void *)(nl->n_value + slide);
        return &iter->result;
    }
    
    return NULL;
}

/*
Example export tree of this library:
             s
            / \
           /   \
          /   ymrez_
         /     / \
        /     /   \
       /    new  init
      r_
     / \
    f  resolve_symbol
   / \
 ree or_each

Consider each node in the export tree a symbol prefix and it's children to be suffixes.
The leaves of the tree represent complete symbols.
 
Traverse the tree in iterative order, accumulating complete symbols by appending the
suffix of the current node to the prefix of the parent node.
 */
SR_INLINE sr_iter_result_t
sr_iter_get_next_export(sr_iterator_t iter) {
    sr_export_iter_t it = &iter->export_iter;
    if (unlikely(it->stack_top == 0)) {
        return NULL;
    }
    
    if (unlikely(it->stack_top >= SR_ITER_STACK_DEPTH)) {
        #ifdef DEBUG
        // Bump SR_ITER_STACK_DEPTH
        abort();
        #endif
        return NULL;
    }
    
    while (it->stack_top > 0) {
        const uint8_t* node = it->node_stack[--it->stack_top].node;
        if (unlikely(!node)) {
            return NULL;
        }
        char* sym = it->node_stack[it->stack_top].sym;
        size_t sym_len = it->node_stack[it->stack_top].sym_len;
        
        const uint8_t *p = node;
        uintptr_t terminal_size = *p++;
        if (unlikely(terminal_size > 127)) {
            --p;
            terminal_size = read_uleb128((void**)&p);
        }
        
        const uint8_t* children = p + terminal_size;
        uint8_t child_count = *children++;
        if (unlikely(child_count == 0)) { // Handle leaf node
            iter->result.symbol = sym;
            iter->result.ptr = (void*)resolve_export_node(++node, iter->symrez->header, sym);
            return &iter->result;
        }
        
        p = children;
        size_t parent_len = sym_len;
        
        // First child needs to be first to get popped so
        // increment stack_top by child_count and iterate
        // over children first to last. Decrement stack_top
        // each time to place siblings from top to bottom,
        // maintaining preorder.
        // The current node is popped and will be replaced
        // by the last child.
        it->stack_top += child_count;
        for (int i = child_count; i > 0; --i) {
            char *child_sym = it->node_stack[--it->stack_top].sym;
            
            // At child_count, stack will be at original
            // (parent) stack_node, which already contains
            // `sym`. Reuse it, saving a memcpy.
            if (likely(i != 1)) {
                memcpy(child_sym, sym, parent_len);
            }
            
            size_t child_len = strlen((char*)p);
            size_t new_len = parent_len + child_len;
            memcpy(&child_sym[parent_len], (char*)p, child_len);
            
            it->node_stack[it->stack_top].sym_len = new_len;
            child_sym[new_len] = '\0';
            
            p += child_len+1;
            
            uintptr_t nodeOffset = read_uleb128((void**)&p);
            if (likely(nodeOffset != 0)) {
                const uint8_t *start = it->start;
                it->node_stack[it->stack_top].node = &start[nodeOffset];
            }
        }
        it->stack_top += child_count;
    }
    return NULL; // No more nodes
}

sr_iter_result_t sr_iter_get_next(sr_iterator_t it) {
    it->result.ptr = NULL;
    it->result.symbol = NULL;
    
    struct sr_symtab_iterator symtab_iter = it->symtab_iter;
    if (symtab_iter.curr < symtab_iter.end) {
        sr_iter_result_t ret = sr_iter_get_next_nlist(it);
        if (likely(ret != NULL)) {
            return ret;
        }
    }

    return sr_iter_get_next_export(it);
}

void sr_iterator_free(sr_iterator_t iterator) {
    free(iterator);
}

sr_iterator_t sr_get_iterator(symrez_t symrez) {
    if (!symrez->iterator) {
        symrez->iterator = sr_iterator_create(symrez);
    }
    
    return symrez->iterator;
}

static bool sr_for_each_handle_node(symrez_t symrez, const uint8_t *node, char *sym, size_t len, symrez_function_t work, void *context) {
    bool stop = false;
    const uint8_t *p = node;
    uintptr_t terminal_size = *p++;
    
    if (unlikely(terminal_size > 127)) {
        --p;
        terminal_size = read_uleb128((void**)&p);
    }
    
    const uint8_t* children = p + terminal_size;
    uint8_t child_count = *children++;
    
    if (unlikely(child_count == 0)) { // Handle leaf node
        void *addr = resolve_export_node(node, symrez->header, sym);
        return work(sym, (void*)addr, context);
    }
    
    p = children;
    for (; child_count > 0; --child_count) {
        size_t child_len = strlen((char*)p);
        strncpy(&sym[len], (char*)p, child_len + 1);
        p += child_len + 1;
        
        uintptr_t offset = read_uleb128((void**)&p);
        if (likely(offset != 0)) {
            const uint8_t *n = &symrez->exports[offset];
            stop = sr_for_each_handle_node(symrez, n, sym, len+child_len, work, context);
            if (unlikely(stop)) break;
        }
    }
    
    return stop;
}

void sr_for_each(symrez_t symrez, void *context, symrez_function_t work) {
    strtab_t strtab = symrez->strtab;
    nlist64_t symtab = symrez->symtab;
    intptr_t slide = symrez->slide;

    void *addr = NULL;
    nlist64_t end = &symtab[symrez->nsyms];
    for (nlist64_t nl = symtab; nl < end; ++nl) {
        if ((nl->n_type & N_STAB) || nl->n_sect == 0 || ((nl->n_type & N_EXT) && symrez->exports)) {
            continue;
        }
        
        char *str = (char *)strtab + nl->n_un.n_strx;
        addr = (void *)(nl->n_value + slide);
        if (unlikely(work(str, addr, context))) {
            return;
        }
    }
    
    if (likely(symrez->exports_size)) {
        void *exports = symrez->exports;
        const uint8_t *start = exports;
        char sym[0x2000] = {0};
        sr_for_each_handle_node(symrez, start, sym, 0, work, context);
    }
}

SR_STATIC void * resolve_local_symbol(symrez_t symrez, const char *symbol) {
    strtab_t strtab = symrez->strtab;
    nlist64_t symtab = symrez->symtab;
    intptr_t slide = symrez->slide;
    
    size_t sym_len = strlen(symbol) + 1;
    uint32_t sym_block = *(uint32_t*)symbol;
    
    nlist64_t end = &symtab[symrez->nsyms];
    for (nlist64_t nl = symtab; nl < end; ++nl) {
        const char *str = (const char *)strtab + nl->n_un.n_strx;
        if (likely(*(uint32_t*)str != sym_block)) continue;
        
        if (likely(sr_strneq(str, symbol, sym_len))) {
            uint64_t n_value = nl->n_value;
            if (likely(n_value > 0)) {
                return (void *)(n_value + slide);
            }
        }
    }
    
    return NULL;
}
 
sr_ptr_t sr_resolve_exported(symrez_t symrez, const char *symbol) {
    if (unlikely(!symrez->exports_size)) {
        return NULL;
    }

    void *addr = NULL;
    void *exportTrie = symrez->exports;
    void *end = (void*)((uintptr_t)exportTrie + symrez->exports_size);
    const uint8_t* node = walk_export_trie(exportTrie, end, symbol);
    if (likely(node)) {
        addr = resolve_export_node(node, symrez->header, symbol);
    }
    
    return addr;
}

SR_STATIC void* resolve_dependent_symbol(symrez_t symrez, const char *symbol) {
    void *addr = NULL;
    mh_for_each_lc(symrez->header, lc) {
        switch (lc->cmd) {
            case LC_REEXPORT_DYLIB:
            case LC_LOAD_UPWARD_DYLIB: {
                const struct dylib_command *dylibCmd = (void*)lc;
                const char *dylib = (char*)((void*)lc + dylibCmd->dylib.name.offset);
                if (unlikely(!dylib)) {
                    break;
                }
                
                struct symrez sr = { 0 };
                mach_header_t hdr = NULL;
                if(unlikely(!(hdr = find_image(dylib)))) {
                    break;
                }
                
                if (unlikely(!symrez_init_mh(&sr, hdr))) {
                    break;
                }
                
                if (lc->cmd == LC_REEXPORT_DYLIB) {
                    addr = sr_resolve_symbol(&sr, symbol);
                } else {
                    addr = resolve_local_symbol(&sr, symbol);
                    if (!addr) {
                        addr = sr_resolve_exported(&sr, symbol);
                    }
                }
                
                if (likely(addr)) {
                    return addr;
                }
            }
        }
    }

    return NULL;
}

#if __has_feature(ptrauth_calls)
SR_INLINE bool
is_symbol_code(symrez_t symrez, sr_ptr_t sym) {
    uint64_t addr = ((uint64_t)sym & ~0xFFFFFF0000000000ULL);
    mh_for_each_lc(symrez->header, lc) {
        if (lc->cmd != LC_SEGMENT_64) continue;
        
        segment_command_t seg = (segment_command_t)lc;
        uint64_t seg_max = (seg->vmaddr + symrez->slide) + seg->vmsize;
        if (addr > seg_max) continue;
        
        section_t sec_start = (section_t)((uint64_t)seg + sizeof(struct segment_command_64));
        const section_t sec_end   = &sec_start[seg->nsects];
        for (section_t sec = sec_start; sec < sec_end; ++sec) {
            uint64_t sec_max = (sec->addr + symrez->slide) + sec->size;
            if (addr > sec_max) continue;
            return ((sec->flags & S_ATTR_PURE_INSTRUCTIONS) || (sec->flags & S_ATTR_SOME_INSTRUCTIONS));
        }
    }
    
    __builtin_unreachable();
}
#endif

sr_ptr_t sr_resolve_symbol(symrez_t symrez, const char *symbol) {
    void *addr = resolve_local_symbol(symrez, symbol);
    
    if (unlikely(!addr)) {
        addr = sr_resolve_exported(symrez, symbol);
        if (unlikely(!addr)) {
            addr = resolve_dependent_symbol(symrez, symbol);
        }
    }
    
#if __has_feature(ptrauth_calls)
    if (unlikely(!addr)) return addr;
    
    if (likely(is_symbol_code(symrez, addr))) {
        addr = ptrauth_sign_unauthenticated(addr, ptrauth_key_function_pointer, 0);
    }
#endif
    
    return addr;
}

void sr_set_slide(symrez_t symrez, intptr_t slide) {
    symrez->slide = slide;
}

intptr_t sr_get_slide(symrez_t symrez) {
    return symrez->slide;
}

void sr_free(symrez_t symrez) {
    if (symrez->iterator) {
        sr_iterator_free(symrez->iterator);
    }
    
    free(symrez);
}

bool symrez_init_mh(symrez_t symrez, mach_header_t mach_header) {
    if (unlikely(!mach_header)) {
        return false;
    }
    
    symrez->header = NULL;
    symrez->slide = 0;
    symrez->nsyms = 0;
    symrez->symtab = NULL;
    symrez->strtab = NULL;
    symrez->exports = NULL;
    symrez->exports_size = 0;
    symrez->iterator = NULL;
    mach_header_t hdr = mach_header;
    
    if (unlikely(hdr == SR_EXEC_HDR)) {
        hdr = get_base_addr();
    } else if (unlikely(hdr == SR_DYLD_HDR)) {
        dyld_all_image_infos_t aii = get_all_image_infos();
        hdr = (mach_header_t)(aii->dyldImageLoadAddress);
    }
    
    intptr_t slide = compute_image_slide(hdr);
    
    symrez->header = hdr;
    symrez->slide = slide;
    
    if (unlikely(!find_linkedit_commands(symrez))) {
        return false;
    }
    
    return true;
}

sr_ptr_t symrez_resolve_once_mh(mach_header_t header, const char *symbol) {
    struct symrez sr;
    if (unlikely(!symrez_init_mh(&sr, header))) {
        return NULL;
    }
    
    return sr_resolve_symbol(&sr, symbol);
}

sr_ptr_t symrez_resolve_once(const char *image_name, const char *symbol) {
    mach_header_t hdr = NULL;
    
    if(unlikely(!(hdr = find_image(image_name)))) {
        return NULL;
    }
    
    return symrez_resolve_once_mh(hdr, symbol);
}

symrez_t symrez_new_mh(mach_header_t mach_header) {
    symrez_t symrez = NULL;
    if (unlikely((symrez = malloc(sizeof(*symrez))) == NULL)) {
        return NULL;
    }
    
    if (unlikely(!symrez_init_mh(symrez, mach_header))) {
        free(symrez);
        symrez = NULL;
    }
    
    return symrez;
}

symrez_t symrez_new(const char *image_name) {
    
    mach_header_t hdr = NULL;
    if(unlikely(!(hdr = find_image(image_name)))) {
        return NULL;
    }

    return symrez_new_mh(hdr);
}
