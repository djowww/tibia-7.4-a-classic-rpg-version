#pragma once

#include <cstdint>
#include <string>
#include <sstream>

#include "position.h"

class WalkMatrix {
public:

    bool inRange(const Position& pos2)
    {
        if (pos.z != pos2.z) return false;
        int32_t xdiff = pos.x - pos2.x;
        int32_t ydiff = pos.y - pos2.y;
        if (std::abs(xdiff) > 3 || std::abs(ydiff) > 3) return false;
        return true;
    }

    int32_t update(const Position& pos2, int32_t value = 0)
    {
        if (pos.z != pos2.z) return 0;
        int32_t xdiff = pos.x - pos2.x;
        int32_t ydiff = pos.y - pos2.y;
        if (std::abs(xdiff) > 3 || std::abs(ydiff) > 3) return 0;
        if (value != 0) {
            matrix[3 - xdiff][3 - ydiff] = value;
            return value;
        }
        counter += 1;
        matrix[3 - xdiff][3 - ydiff] = counter;
        return counter;
    }

    int32_t get(const Position& pos2)
    {
        if (pos.z != pos2.z) return 0;
        int32_t xdiff = pos.x - pos2.x;
        int32_t ydiff = pos.y - pos2.y;
        if (std::abs(xdiff) > 3 || std::abs(ydiff) > 3) return 0;
        return matrix[3 - xdiff][3 - ydiff];
    }

    void clear()
    {
        for (auto& x : matrix) {
            for (auto& y : x) {
                y = 0;
            }
        }
    }

    uint32_t reset(uint32_t value = 0)
    {
        if (value == 0) {
            counter += 1;
            value = counter;
        }
        for (auto& x : matrix) {
            for (auto& y : x) {
                y = value;
            }
        }
        return value;
    }

private:
    Position pos;
    int32_t matrix[7][7] = { { 0 } };
    int32_t counter = 0;
}; 