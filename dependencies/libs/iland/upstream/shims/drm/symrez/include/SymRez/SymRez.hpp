#ifndef __SYMREZ_HPP__
#define __SYMREZ_HPP__
#if defined(__cplusplus)
#include <SymRez/Core.h>

#include <string>
#include <memory>
#include <iterator>
#include <functional>

#ifndef _LIBCPP_CONSTEXPR_SINCE_CXX14
#if _LIBCPP_STD_VER >= 14
#define _LIBCPP_CONSTEXPR_SINCE_CXX14 constexpr
#else
#define _LIBCPP_CONSTEXPR_SINCE_CXX14
#endif
#endif

#ifndef sr_contexpr_14
#define sr_contexpr_14 _LIBCPP_CONSTEXPR_SINCE_CXX14
#endif

namespace {
struct SymRez {
public:
    struct iterator {
    public:
        
        struct IteratorEntry {
        public:
            inline const std::string_view& name() const {
                return name_;
            }
            
            inline void* address() const {
                return address_;
            }
            
        private:
            friend SymRez::iterator;
            inline IteratorEntry(sr_iterator_t i) {
                if (i == nullptr) [[unlikely]] {
                    name_ = "";
                    address_ = nullptr;
                    return;
                }
                setName(i);
                address_ = sr_iter_get_ptr(i);
            }
            
            #if _LIBCPP_STD_VER >= 17
            IteratorEntry(const IteratorEntry&) = delete;
            IteratorEntry& operator=(const IteratorEntry&) = delete;
            #endif
            
            inline sr_contexpr_14 void setName(std::string_view name) {
                name_ = name;
            }
            
            inline sr_contexpr_14 void setName(sr_iterator_t it) {
                sr_symbol_t n = sr_iter_get_symbol(it);
                name_ = n ? n : "";
            }
            
            inline sr_contexpr_14 void setAddress(void *address) {
                address_ = address;
            }
            
            inline sr_contexpr_14 void setAddress(sr_iterator_t it) {
                void *a = sr_iter_get_ptr(it);
                setAddress(a);
            }
            
            inline sr_contexpr_14 void update(sr_iterator_t it) {
                setName(it);
                setAddress(it);
            }
            
            std::string_view name_;
            void* address_;
        };
        
        using iterator_category = std::forward_iterator_tag;
        using value_type = IteratorEntry;
        using difference_type = std::ptrdiff_t;
        using pointer = IteratorEntry *;
        using reference = IteratorEntry &;
        using const_pointer = const IteratorEntry *;
        using const_reference = const IteratorEntry &;
        
        inline iterator(sr_iterator_t iter)
        : iter_(iter), current_(iter) {}
        
        inline iterator(symrez_t sr)
        : iter_(sr_get_iterator(sr)), current_(nullptr) {
            sr_iter_reset(iter_);
            sr_iter_get_next(iter_);
            current_.update(iter_);
        }
        
        #if _LIBCPP_STD_VER >= 17
        iterator(const iterator&) = delete;
        iterator& operator=(const iterator&) = delete;
        #endif
        
        inline constexpr const_pointer operator->() const { return &current_; }
        
        inline constexpr const_reference &operator*() const { return current_; }
        
        inline constexpr bool operator==(const iterator &other) const {
            return  current_.address() == other.current_.address();
        }
        
        inline constexpr bool operator!=(const iterator &other) const {
            return !(*this == other);
        }
        
        inline sr_contexpr_14 iterator &operator++() {
            sr_iter_get_next(iter_);
            current_.update(iter_);
            return *this;
        }
        
        inline void reset() {
            sr_iter_reset(iter_);
            (void)++(*this);
        }
        
    private:
        sr_iterator_t iter_;
        IteratorEntry current_;
    };
    
    using IteratorEntry = SymRez::iterator::IteratorEntry;
    
    inline SymRez(const std::string_view& image_name)
    : symrez_(symrez_new(image_name.data()), sr_free) {}
    
    inline SymRez(mach_header_t& header)
    : symrez_(symrez_new_mh(header), sr_free) {}
    
    SymRez(const SymRez&) = delete;
    SymRez& operator=(const SymRez&) = delete;
    
    inline explicit operator bool() const {
        return bool(symrez_);
    }
    
    static inline void* ResolveOnce(const std::string_view& image_name, const std::string_view& symbol) {
        return symrez_resolve_once(image_name.data(), symbol.data());
    }
    
    static inline void* ResolveOnce(mach_header_t& image, const std::string_view& symbol) {
        return symrez_resolve_once_mh(image, symbol.data());
    }
    
    template<typename ReturnType, typename... Args, typename FunctionType = ReturnType(*)(Args...)>
    inline FunctionType resolveSymbol(const std::string_view& symbol) const {
        return reinterpret_cast<FunctionType>(sr_resolve_symbol(symrez_.get(), symbol.data()));
    }
    
    template<typename ReturnType, typename... Args, typename FunctionType = ReturnType(*)(Args...)>
    inline FunctionType resolveExportedSymbol(const std::string_view& symbol) const {
        return reinterpret_cast<FunctionType>(sr_resolve_exported(symrez_.get(), symbol.data()));
    }
    
    inline iterator begin() const {
        sr_iterator_t it = sr_get_iterator(symrez_.get());
        sr_iter_reset(it);
        sr_iter_get_next(it);
        return iterator(it);
    }
    
    inline iterator end() const {
        return iterator((sr_iterator_t)nullptr);
    }

    inline sr_contexpr_14 void setSlide(intptr_t slide) const {
        sr_set_slide(symrez_.get(), slide);
    }
    
    inline constexpr intptr_t getSlide() const {
        return sr_get_slide(symrez_.get());
    }
    
private:
    std::unique_ptr<symrez, decltype(&sr_free)> symrez_;
//    symrez_t symrez_;
};
}

#endif //__cplusplus
#endif
