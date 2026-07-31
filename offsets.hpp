/*
 * Auto-converted from valkz-dumper (no imtheo)
 * Roblox Version: version-145f189a6a974303
 */

#pragma once
#include <cstdint>

// clang-format off
namespace offsets {
    inline char roblox_version[64] = "version-145f189a6a974303";

    namespace BasePart {
         inline uintptr_t CastShadow = 0xD5;
         inline uintptr_t Color3 = 0x148;
         inline uintptr_t Locked = 0xD6;
         inline uintptr_t Massless = 0xD7;
         inline uintptr_t Primitive = 0x128;
         inline uintptr_t Reflectance = 0xCC;
         inline uintptr_t Shape = 0x159;
         inline uintptr_t Transparency = 0xD0;
    }

    namespace BloomEffect {
         inline uintptr_t Intensity = 0xB8;
         inline uintptr_t Size = 0xBC;
         inline uintptr_t Threshold = 0xC0;
    }

    namespace ByteCode {
         inline uintptr_t Pointer = 0x10;
         inline uintptr_t Size = 0x20;
    }

    namespace Camera {
         inline uintptr_t CFrame = 0xD8;
         inline uintptr_t CameraSubject = 0xC8;
         inline uintptr_t CameraType = 0x144;
         inline uintptr_t FieldOfView = 0x140;
         inline uintptr_t Position = 0xFC;
         inline uintptr_t Rotation = 0xD8;
         inline uintptr_t Viewport = 0x2E0;
         inline uintptr_t ViewportSize = 0x2C8;
    }

    namespace CharacterMesh {
         inline uintptr_t BaseTextureId = 0xC8;
         inline uintptr_t BodyPart = 0x148;
         inline uintptr_t MeshId = 0xF8;
         inline uintptr_t OverlayTextureId = 0x128;
    }

    namespace DataModel {
         inline uintptr_t CreatorId = 0x180;
         inline uintptr_t GameId = 0x188;
         inline uintptr_t GameLoaded = 0x578;
         inline uintptr_t JobId = 0x120;
         inline uintptr_t PlaceId = 0x190;
         inline uintptr_t ServerIP = 0x560;
         inline uintptr_t Workspace = 0x160;
    }

    namespace FakeDataModel {
         inline uintptr_t Pointer = 0x7E26978;
         inline uintptr_t RealDataModel = 0x1D0;
    }

    namespace GuiBase2D {
         inline uintptr_t AbsolutePosition = 0xF4;
         inline uintptr_t AbsoluteRotation = 0x178;
         inline uintptr_t AbsoluteSize = 0x100;
    }

    namespace GuiObject {
         inline uintptr_t Active = 0x5A8;
         inline uintptr_t AnchorPoint = 0x558;
         inline uintptr_t AutomaticSize = 0x560;
         inline uintptr_t BackgroundColor3 = 0x540;
         inline uintptr_t BackgroundTransparency = 0x564;
         inline uintptr_t BorderColor3 = 0x54C;
         inline uintptr_t BorderMode = 0x568;
         inline uintptr_t BorderSizePixel = 0x56C;
         inline uintptr_t ClipsDescendants = 0x5A9;
         inline uintptr_t GuiState = 0x578;
         inline uintptr_t Interactable = 0x5AB;
         inline uintptr_t LayoutOrder = 0x580;
         inline uintptr_t Position = 0x510;
         inline uintptr_t Rotation = 0x178;
         inline uintptr_t Selectable = 0x5AC;
         inline uintptr_t SelectionOrder = 0x59C;
         inline uintptr_t Size = 0x530;
         inline uintptr_t SizeConstraint = 0x5A0;
         inline uintptr_t Visible = 0x5AD;
         inline uintptr_t ZIndex = 0x5A4;
    }

    namespace Humanoid {
         inline uintptr_t AutoJumpEnabled = 0x1D4;
         inline uintptr_t AutoRotate = 0x1D5;
         inline uintptr_t AutomaticScalingEnabled = 0x1D6;
         inline uintptr_t BreakJointsOnDeath = 0x1D7;
         inline uintptr_t CameraOffset = 0x128;
         inline uintptr_t DisplayDistanceType = 0x180;
         inline uintptr_t EvaluateStateMachine = 0x1D8;
         inline uintptr_t Health = 0x190;
         inline uintptr_t HealthDisplayDistance = 0x188;
         inline uintptr_t HealthDisplayType = 0x18C;
         inline uintptr_t HipHeight = 0x194;
         inline uintptr_t HumanoidState = 0x898;
         inline uintptr_t HumanoidStateID = 0x20;
         inline uintptr_t Jump = 0x1D0;
         inline uintptr_t JumpHeight = 0x1A0;
         inline uintptr_t JumpPower = 0x1A4;
         inline uintptr_t MaxHealth = 0x1A8;
         inline uintptr_t MaxSlopeAngle = 0x1AC;
         inline uintptr_t NameDisplayDistance = 0x1B0;
         inline uintptr_t NameOcclusion = 0x1B4;
         inline uintptr_t PlatformStand = 0x1DC;
         inline uintptr_t RequiresNeck = 0x1DD;
         inline uintptr_t RigType = 0x3D;
         inline uintptr_t SeatPart = 0x108;
         inline uintptr_t Sit = 0x1DE;
         inline uintptr_t TargetPoint = 0x14C;
         inline uintptr_t UseJumpPower = 0x1E0;
         inline uintptr_t WalkSpeed = 0x1D0;
         inline uintptr_t WalkSpeedCheck = 0x3BC;
         inline uintptr_t WalkToPoint = 0x164;
         inline uintptr_t Walkspeed = 0x1D0;
         inline uintptr_t WalkspeedCheck = 0x3BC;
    }

    namespace InputObject {
         inline uintptr_t MousePosition = 0xD4;
    }

    namespace Instance {
         inline uintptr_t ChildrenEnd = 0x8;
         inline uintptr_t ChildrenStart = 0x70;
         inline uintptr_t ClassDescriptor = 0x18;
         inline uintptr_t ClassName = 0x8;
         inline uintptr_t ComponentMap = 0x38;
         inline uintptr_t Name = 0x98;
         inline uintptr_t Parent = 0x68;
    }

    namespace Lighting {
         inline uintptr_t Ambient = 0xD0;
         inline uintptr_t Atmosphere = 0x1D0;
         inline uintptr_t Brightness = 0x118;
         inline uintptr_t ClockTime = 0xC8;
         inline uintptr_t ColorShift_Bottom = 0xDC;
         inline uintptr_t ColorShift_Top = 0xE8;
         inline uintptr_t EnvironmentDiffuseScale = 0x11C;
         inline uintptr_t EnvironmentSpecularScale = 0x120;
         inline uintptr_t ExposureCompensation = 0x124;
         inline uintptr_t FogColor = 0xF4;
         inline uintptr_t FogEnd = 0x12C;
         inline uintptr_t FogStart = 0x130;
         inline uintptr_t GlobalShadows = 0x138;
         inline uintptr_t OutdoorAmbient = 0x100;
         inline uintptr_t ShadowSoftness = 0x13C;
         inline uintptr_t Sky = 0x1C0;
    }

    namespace LightingParameters {
         inline uintptr_t GeographicLatitude = 0x134;
         inline uintptr_t LightColor = 0x154;
         inline uintptr_t LightDirection = 0x160;
         inline uintptr_t SkyAmbient = 0x148;
         inline uintptr_t SkyAmbient2 = 0x138;
         inline uintptr_t Source = 0x16C;
         inline uintptr_t TrueMoonPosition = 0x17C;
         inline uintptr_t TrueSunPosition = 0x170;
    }

    namespace LocalScript {
         inline uintptr_t Bytecode = 0x190;
         inline uintptr_t Hash = 0x98;
    }

    namespace MaterialColors {
         inline uintptr_t Asphalt = 0x30;
         inline uintptr_t Basalt = 0x27;
         inline uintptr_t Brick = 0xF;
         inline uintptr_t Cobblestone = 0x33;
         inline uintptr_t Concrete = 0xC;
         inline uintptr_t CrackedLava = 0x2D;
         inline uintptr_t Glacier = 0x1B;
         inline uintptr_t Grass = 0x6;
         inline uintptr_t Ground = 0x2A;
         inline uintptr_t Ice = 0x36;
         inline uintptr_t LeafyGrass = 0x39;
         inline uintptr_t Limestone = 0x3F;
         inline uintptr_t Mud = 0x24;
         inline uintptr_t Pavement = 0x42;
         inline uintptr_t Rock = 0x18;
         inline uintptr_t Salt = 0x3C;
         inline uintptr_t Sand = 0x12;
         inline uintptr_t Sandstone = 0x21;
         inline uintptr_t Slate = 0x9;
         inline uintptr_t Snow = 0x1E;
         inline uintptr_t WoodPlanks = 0x15;
    }

    namespace MeshPart {
         inline uintptr_t MeshId = 0x2A8;
         inline uintptr_t TextureId = 0x2D8;
    }

    namespace Misc {
         inline uintptr_t AnimationId = 0xC0;
    }

    namespace ModuleScript {
         inline uintptr_t Bytecode = 0x138;
         inline uintptr_t Hash = 0x148;
    }

    namespace MouseService {
         inline uintptr_t InputObject = 0x100;
         inline uintptr_t InputObject2 = 0xF0;
         inline uintptr_t MousePosition = 0xD4;
    }

    namespace Player {
         inline uintptr_t AccountAge = 0x35C;
         inline uintptr_t Character = 0x298;
         inline uintptr_t DisplayName = 0x138;
         inline uintptr_t HealthDisplayDistance = 0x390;
         inline uintptr_t LocalPlayer = 0x130;
         inline uintptr_t LocaleId = 0x740;
         inline uintptr_t MaxZoomDistance = 0x368;
         inline uintptr_t MinZoomDistance = 0x36C;
         inline uintptr_t ModelInstance = 0x298;
         inline uintptr_t NameDisplayDistance = 0x3A0;
         inline uintptr_t Team = 0x2D8;
         inline uintptr_t TeamColor = 0x3AC;
         inline uintptr_t UserId = 0xD0;
    }

    namespace Players {
         inline uintptr_t LocalPlayer = 0x130;
    }

    namespace Primitive {
         inline uintptr_t AssemblyAngularVelocity = 0x104;
         inline uintptr_t AssemblyLinearVelocity = 0xF8;
         inline uintptr_t CFrame = 0xC8;
         inline uintptr_t Flags = 0x1B6;
         inline uintptr_t Material = 0x23E;
         inline uintptr_t Orientation = 0xC8;
         inline uintptr_t Owner = 0x208;
         inline uintptr_t Position = 0xEC;
         inline uintptr_t PrimitiveFlags = 0x1B6;
         inline uintptr_t Rotation = 0xC8;
         inline uintptr_t Size = 0x1B8;
         inline uintptr_t Validate = 0x6;
    }

    namespace PrimitiveFlags {
         inline uintptr_t Anchored = 0x2;
         inline uintptr_t CanCollide = 0x8;
         inline uintptr_t CanQuery = 0x20;
         inline uintptr_t CanTouch = 0x10;
    }

    namespace ProximityPrompt {
         inline uintptr_t ActionText = 0xB0;
         inline uintptr_t Enabled = 0x136;
         inline uintptr_t HoldDuration = 0x120;
         inline uintptr_t KeyboardKeyCode = 0x124;
         inline uintptr_t MaxActivationDistance = 0x128;
         inline uintptr_t ObjectText = 0xD0;
         inline uintptr_t RequiresLineOfSight = 0x137;
    }

    namespace RenderView {
         inline uintptr_t LightingValid = 0x228;
         inline uintptr_t SkyboxValid = 0x28D;
    }

    namespace Seat {
         inline uintptr_t Occupant = 0x1B0;
    }

    namespace Sky {
         inline uintptr_t MoonAngularSize = 0x244;
         inline uintptr_t MoonTextureId = 0xC8;
         inline uintptr_t SkyboxBk = 0xF8;
         inline uintptr_t SkyboxDn = 0x128;
         inline uintptr_t SkyboxFt = 0x158;
         inline uintptr_t SkyboxLf = 0x188;
         inline uintptr_t SkyboxOrientation = 0x238;
         inline uintptr_t SkyboxRt = 0x1B8;
         inline uintptr_t SkyboxUp = 0x1E8;
         inline uintptr_t StarCount = 0x248;
         inline uintptr_t SunAngularSize = 0x24C;
         inline uintptr_t SunTextureId = 0x218;
    }

    namespace SpecialMesh {
         inline uintptr_t MeshId = 0xF8;
         inline uintptr_t Offset = 0xB8;
         inline uintptr_t Scale = 0xC4;
         inline uintptr_t TextureId = 0x128;
    }

    namespace StatsItem {
         inline uintptr_t Value = 0xB8;
    }

    namespace TaskScheduler {
         inline uintptr_t JobEnd = 0xD0;
         inline uintptr_t JobName = 0x8E0;
         inline uintptr_t JobStart = 0xC8;
         inline uintptr_t Pointer = 0x84A58E0;
    }

    namespace Team {
         inline uintptr_t BrickColor = 0xB8;
         inline uintptr_t TeamColor = 0xB8;
    }

    namespace Terrain {
         inline uintptr_t GrassLength = 0x188;
         inline uintptr_t MaterialColors = 0x430;
         inline uintptr_t WaterColor = 0x178;
         inline uintptr_t WaterReflectance = 0x190;
         inline uintptr_t WaterTransparency = 0x194;
         inline uintptr_t WaterWaveSize = 0x198;
         inline uintptr_t WaterWaveSpeed = 0x19C;
    }

    namespace TextButton {
         inline uintptr_t AutoButtonColor = 0x9C4;
         inline uintptr_t ContentText = 0xDF8;
         inline uintptr_t Font = 0x1130;
         inline uintptr_t LineHeight = 0xF10;
         inline uintptr_t LocalizedText = 0xDF8;
         inline uintptr_t MaxVisibleGraphemes = 0x113C;
         inline uintptr_t Modal = 0x9C5;
         inline uintptr_t RichText = 0x100E;
         inline uintptr_t Selected = 0x9C6;
         inline uintptr_t Text = 0xDF8;
         inline uintptr_t TextColor3 = 0x1118;
         inline uintptr_t TextDirection = 0xFB0;
         inline uintptr_t TextScaled = 0xDE1;
         inline uintptr_t TextSize = 0x1144;
         inline uintptr_t TextStrokeColor3 = 0x1124;
         inline uintptr_t TextStrokeTransparency = 0x1148;
         inline uintptr_t TextTransparency = 0x114C;
         inline uintptr_t TextTruncate = 0x1150;
         inline uintptr_t TextWrapped = 0x1008;
         inline uintptr_t TextXAlignment = 0x1154;
         inline uintptr_t TextYAlignment = 0xF58;
    }

    namespace TextLabel {
         inline uintptr_t ContentText = 0xB78;
         inline uintptr_t Font = 0xEB0;
         inline uintptr_t LineHeight = 0xC90;
         inline uintptr_t LocalizedText = 0xB78;
         inline uintptr_t MaxVisibleGraphemes = 0xEBC;
         inline uintptr_t RichText = 0xD8E;
         inline uintptr_t Text = 0xB78;
         inline uintptr_t TextColor3 = 0xE98;
         inline uintptr_t TextDirection = 0xD30;
         inline uintptr_t TextScaled = 0xD86;
         inline uintptr_t TextSize = 0xEC4;
         inline uintptr_t TextStrokeColor3 = 0xEA4;
         inline uintptr_t TextStrokeTransparency = 0xEC8;
         inline uintptr_t TextTransparency = 0xECC;
         inline uintptr_t TextTruncate = 0xED0;
         inline uintptr_t TextWrapped = 0xD88;
         inline uintptr_t TextXAlignment = 0xED4;
         inline uintptr_t TextYAlignment = 0xCD8;
    }

    namespace Tool {
         inline uintptr_t CanBeDropped = 0x4B8;
         inline uintptr_t Enabled = 0x4B9;
         inline uintptr_t Grip = 0x488;
         inline uintptr_t GripForward = 0x4A0;
         inline uintptr_t GripPos = 0x4AC;
         inline uintptr_t GripRight = 0x488;
         inline uintptr_t GripUp = 0x494;
         inline uintptr_t ManualActivationOnly = 0x4BA;
         inline uintptr_t RequiresHandle = 0x4BB;
         inline uintptr_t Tooltip = 0x468;
    }

    namespace Value {
         inline uintptr_t Value = 0xB8;
    }

    namespace VehicleSeat {
         inline uintptr_t MaxSpeed = 0x1C8;
         inline uintptr_t Occupant = 0x1A8;
         inline uintptr_t SteerFloat = 0x1D0;
         inline uintptr_t ThrottleFloat = 0x1D8;
         inline uintptr_t Torque = 0x1DC;
         inline uintptr_t TurnSpeed = 0x1E0;
    }

    namespace VisualEngine {
         inline uintptr_t Dimensions = 0xAE0;
         inline uintptr_t FakeDataModel = 0xAC0;
         inline uintptr_t Pointer = 0x8818F60;
         inline uintptr_t RenderView = 0xBF0;
         inline uintptr_t ViewMatrix = 0x180;
    }

    namespace Workspace {
         inline uintptr_t CurrentCamera = 0x498;
         inline uintptr_t Raycast = 0x0;
         inline uintptr_t ReadOnlyGravity = 0x9B0;
         inline uintptr_t World = 0x3F0;
    }

    namespace World {
         inline uintptr_t FallenPartsDestroyHeight = 0x208;
         inline uintptr_t Gravity = 0x210;
         inline uintptr_t Primitives = 0x288;
         inline uintptr_t WorldSteps = 0x700;
         inline uintptr_t worldStepsPerSec = 0x700;
    }

    namespace WorldRoot {
         inline uintptr_t FindPartOnRayDescriptorRva = 0x611D080;
         inline uintptr_t FindPartOnRayWithIgnoreListDescriptorRva = 0x611D090;
         inline uintptr_t FindPartOnRayWithWhitelistDescriptorRva = 0x611D0A0;
         inline uintptr_t RaycastBoundFunctionOffset = 0x80;
         inline uintptr_t RaycastCompleteObjectLocatorRva = 0x71003B8;
         inline uintptr_t RaycastDescriptorRva = 0x8091390;
         inline uintptr_t RaycastDescriptorVtableRva = 0x65EB9E8;
         inline uintptr_t RaycastTypeDescriptorRva = 0x7D4C460;
    }

}
// clang-format on
