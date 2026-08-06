/*
 * Dumped With: valkz-dumper 1.0
 * Created by: Valkz (JustValkz)
 * Github: https://github.com/JustValkz/Myst
 * Roblox Version: version-d584fb6c717a43d9
 * Time Taken: 68607 ms (68.607000 seconds)
 * Total Offsets: 17
 */

#pragma once
#include <cstdint>

// clang-format off
namespace offsets {
    inline constexpr const char* roblox_version = "version-d584fb6c717a43d9";

    namespace DataModel {
        inline constexpr uintptr_t Workspace = 0x160;
    }

    namespace FakeDataModel {
        inline constexpr uintptr_t Pointer = 0x8A5D748;
        inline constexpr uintptr_t RealDataModel = 0x1D0;
    }

    namespace RenderView {
        inline constexpr uintptr_t LightingValid = 0x228;
        inline constexpr uintptr_t SkyboxValid = 0x28D;
    }

    namespace VisualEngine {
        inline constexpr uintptr_t FakeDataModel = 0xAC0;
        inline constexpr uintptr_t Pointer = 0x811D0A0;
        inline constexpr uintptr_t RenderView = 0xBF0;
        inline constexpr uintptr_t ViewMatrix = 0x180;
    }

    namespace WorldRoot {
        inline constexpr uintptr_t FindPartOnRayDescriptorRva = 0x6854420;
        inline constexpr uintptr_t FindPartOnRayWithIgnoreListDescriptorRva = 0x6854430;
        inline constexpr uintptr_t FindPartOnRayWithWhitelistDescriptorRva = 0x6854440;
        inline constexpr uintptr_t RaycastBoundFunctionOffset = 0x80;
        inline constexpr uintptr_t RaycastCompleteObjectLocatorRva = 0x7093638;
        inline constexpr uintptr_t RaycastDescriptorRva = 0x81E7150;
        inline constexpr uintptr_t RaycastDescriptorVtableRva = 0x61744C8;
        inline constexpr uintptr_t RaycastTypeDescriptorRva = 0x7C961A0;
    }

} // namespace offsets
