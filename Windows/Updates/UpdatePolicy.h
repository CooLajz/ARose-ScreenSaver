#pragma once
#include <cstdint>
namespace updates {
inline bool due(uint64_t last,uint64_t now) {
    return last==0 || now<last || now-last>=604800;
}
}
