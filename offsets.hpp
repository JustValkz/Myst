/*
 * Myst offsets mirror — fallback when https://offsets.imtheo.lol/Offsets.hpp is blocked.
 * Source: bundled_offsets.h (theo dump)
 * Roblox Version: version-36a2600cebf1487d
 */

#pragma once
#include <cstdint>

// clang-format off
namespace offsets {
    inline constexpr const char* roblox_version = "version-36a2600cebf1487d";

    namespace AirProperties {
        inline constexpr uintptr_t AirDensity = 0x18;
        inline constexpr uintptr_t GlobalWind = 0x3C;
    }

    namespace AnimationTrack {
        inline constexpr uintptr_t Animation = 0xB8;
        inline constexpr uintptr_t Animator = 0x108;
        inline constexpr uintptr_t IsPlaying = 0xA90;
        inline constexpr uintptr_t Looped = 0xE5;
        inline constexpr uintptr_t Speed = 0xD4;
        inline constexpr uintptr_t TimePosition = 0xD8;
    }

    namespace Animator {
        inline constexpr uintptr_t ActiveAnimations = 0xA20;
    }

    namespace Atmosphere {
        inline constexpr uintptr_t Color = 0xB8;
        inline constexpr uintptr_t Decay = 0xC4;
        inline constexpr uintptr_t Density = 0xD0;
        inline constexpr uintptr_t Glare = 0xD4;
        inline constexpr uintptr_t Haze = 0xD8;
        inline constexpr uintptr_t Offset = 0xDC;
    }

    namespace Attachment {
        inline constexpr uintptr_t Position = 0xC4;
    }

    namespace Attribute {
        inline constexpr uintptr_t Key = 0x0;
        inline constexpr uintptr_t Size = 0x58;
        inline constexpr uintptr_t Value = 0x18;
    }

    namespace AttributesMap {
        inline constexpr uintptr_t Attributes = 0x10;
        inline constexpr uintptr_t Length = 0x0;
    }

    namespace BasePart {
        inline constexpr uintptr_t CastShadow = 0xD5;
        inline constexpr uintptr_t Color3 = 0x148;
        inline constexpr uintptr_t Locked = 0xD6;
        inline constexpr uintptr_t Massless = 0xD7;
        inline constexpr uintptr_t Primitive = 0x128;
        inline constexpr uintptr_t Reflectance = 0xCC;
        inline constexpr uintptr_t Shape = 0x159;
        inline constexpr uintptr_t Transparency = 0xD0;
    }

    namespace Beam {
        inline constexpr uintptr_t Attachment0 = 0x160;
        inline constexpr uintptr_t Attachment1 = 0x170;
        inline constexpr uintptr_t Brightness = 0x180;
        inline constexpr uintptr_t CurveSize0 = 0x184;
        inline constexpr uintptr_t CurveSize1 = 0x188;
        inline constexpr uintptr_t LightEmission = 0x18C;
        inline constexpr uintptr_t LightInfluence = 0x190;
        inline constexpr uintptr_t Texture = 0x140;
        inline constexpr uintptr_t TextureLength = 0x19C;
        inline constexpr uintptr_t TextureSpeed = 0x1A4;
        inline constexpr uintptr_t Width0 = 0x1A8;
        inline constexpr uintptr_t Width1 = 0x1AC;
        inline constexpr uintptr_t ZOffset = 0x1B0;
    }

    namespace BloomEffect {
        inline constexpr uintptr_t Enabled = 0xB0;
        inline constexpr uintptr_t Intensity = 0xB8;
        inline constexpr uintptr_t Size = 0xBC;
        inline constexpr uintptr_t Threshold = 0xC0;
    }

    namespace BlurEffect {
        inline constexpr uintptr_t Enabled = 0xB0;
        inline constexpr uintptr_t Size = 0xB8;
    }

    namespace ByteCode {
        inline constexpr uintptr_t Pointer = 0x10;
        inline constexpr uintptr_t Size = 0x20;
    }

    namespace Camera {
        inline constexpr uintptr_t CameraSubject = 0xC8;
        inline constexpr uintptr_t CameraType = 0x138;
        inline constexpr uintptr_t FieldOfView = 0x140;
        inline constexpr uintptr_t ImagePlaneDepth = 0x2D0;
        inline constexpr uintptr_t Position = 0xFC;
        inline constexpr uintptr_t Rotation = 0xD8;
        inline constexpr uintptr_t Viewport = 0x28C;
        inline constexpr uintptr_t ViewportSize = 0x2C8;
    }

    namespace CharacterMesh {
        inline constexpr uintptr_t BaseTextureId = 0xC8;
        inline constexpr uintptr_t BodyPart = 0x148;
        inline constexpr uintptr_t MeshId = 0xF8;
        inline constexpr uintptr_t OverlayTextureId = 0x128;
    }

    namespace ClickDetector {
        inline constexpr uintptr_t MaxActivationDistance = 0xE8;
        inline constexpr uintptr_t MouseIcon = 0xC8;
    }

    namespace Clothing {
        inline constexpr uintptr_t Color3 = 0x120;
        inline constexpr uintptr_t Template = 0x100;
    }

    namespace ColorCorrectionEffect {
        inline constexpr uintptr_t Brightness = 0xC4;
        inline constexpr uintptr_t Contrast = 0xC8;
        inline constexpr uintptr_t Enabled = 0xB0;
        inline constexpr uintptr_t TintColor = 0xB8;
    }

    namespace ColorGradingEffect {
        inline constexpr uintptr_t Enabled = 0xB0;
        inline constexpr uintptr_t TonemapperPreset = 0xB8;
    }

    namespace DataModel {
        inline constexpr uintptr_t CreatorId = 0x180;
        inline constexpr uintptr_t GameId = 0x188;
        inline constexpr uintptr_t GameLoaded = 0x668;
        inline constexpr uintptr_t JobId = 0x120;
        inline constexpr uintptr_t PlaceId = 0x190;
        inline constexpr uintptr_t PlaceVersion = 0x1AC;
        inline constexpr uintptr_t PrimitiveCount = 0x498;
        inline constexpr uintptr_t ScriptContext = 0x440;
        inline constexpr uintptr_t ServerIP = 0x650;
        inline constexpr uintptr_t ToRenderView1 = 0x1C8;
        inline constexpr uintptr_t ToRenderView2 = 0x8;
        inline constexpr uintptr_t ToRenderView3 = 0x28;
        inline constexpr uintptr_t Workspace = 0x160;
    }

    namespace DepthOfFieldEffect {
        inline constexpr uintptr_t Enabled = 0xB0;
        inline constexpr uintptr_t FarIntensity = 0xB8;
        inline constexpr uintptr_t FocusDistance = 0xBC;
        inline constexpr uintptr_t InFocusRadius = 0xC0;
        inline constexpr uintptr_t NearIntensity = 0xC4;
    }

    namespace DragDetector {
        inline constexpr uintptr_t ActivatedCursorIcon = 0x1C0;
        inline constexpr uintptr_t CursorIcon = 0xC8;
        inline constexpr uintptr_t MaxActivationDistance = 0xE8;
        inline constexpr uintptr_t MaxDragAngle = 0x2A8;
        inline constexpr uintptr_t MaxDragTranslation = 0x26C;
        inline constexpr uintptr_t MaxForce = 0x2AC;
        inline constexpr uintptr_t MaxTorque = 0x2B0;
        inline constexpr uintptr_t MinDragAngle = 0x2B4;
        inline constexpr uintptr_t MinDragTranslation = 0x278;
        inline constexpr uintptr_t ReferenceInstance = 0x1F0;
        inline constexpr uintptr_t Responsiveness = 0x2C0;
    }

    namespace FakeDataModel {
        inline constexpr uintptr_t Pointer = 0x84A9E98;
        inline constexpr uintptr_t RealDataModel = 0x1D0;
    }

    namespace GuiBase2D {
        inline constexpr uintptr_t AbsolutePosition = 0xF8;
        inline constexpr uintptr_t AbsoluteRotation = 0x178;
        inline constexpr uintptr_t AbsoluteSize = 0x100;
    }

    namespace GuiObject {
        inline constexpr uintptr_t BackgroundColor3 = 0x540;
        inline constexpr uintptr_t BackgroundTransparency = 0x54C;
        inline constexpr uintptr_t BorderColor3 = 0x54C;
        inline constexpr uintptr_t Image = 0x988;
        inline constexpr uintptr_t LayoutOrder = 0x580;
        inline constexpr uintptr_t Position = 0x510;
        inline constexpr uintptr_t RichText = 0xB50;
        inline constexpr uintptr_t Rotation = 0x178;
        inline constexpr uintptr_t ScreenGui_Enabled = 0x4C4;
        inline constexpr uintptr_t Size = 0x530;
        inline constexpr uintptr_t Text = 0xDA0;
        inline constexpr uintptr_t TextColor3 = 0xE50;
        inline constexpr uintptr_t Visible = 0x5AD;
        inline constexpr uintptr_t ZIndex = 0x18B;
    }

    namespace Humanoid {
        inline constexpr uintptr_t AutoJumpEnabled = 0x1D4;
        inline constexpr uintptr_t AutoRotate = 0x1D5;
        inline constexpr uintptr_t AutomaticScalingEnabled = 0x1D6;
        inline constexpr uintptr_t BreakJointsOnDeath = 0x1D7;
        inline constexpr uintptr_t CameraOffset = 0x128;
        inline constexpr uintptr_t DisplayDistanceType = 0x180;
        inline constexpr uintptr_t DisplayName = 0xB8;
        inline constexpr uintptr_t EvaluateStateMachine = 0x1D8;
        inline constexpr uintptr_t FloorMaterial = 0x184;
        inline constexpr uintptr_t Health = 0x188;
        inline constexpr uintptr_t HealthDisplayDistance = 0x18C;
        inline constexpr uintptr_t HealthDisplayType = 0x190;
        inline constexpr uintptr_t HipHeight = 0x194;
        inline constexpr uintptr_t HumanoidRootPart = 0x478;
        inline constexpr uintptr_t HumanoidState = 0x898;
        inline constexpr uintptr_t HumanoidStateID = 0x20;
        inline constexpr uintptr_t IsWalking = 0x917;
        inline constexpr uintptr_t Jump = 0x1DA;
        inline constexpr uintptr_t JumpHeight = 0x1A0;
        inline constexpr uintptr_t JumpPower = 0x1A4;
        inline constexpr uintptr_t MaxHealth = 0x1A8;
        inline constexpr uintptr_t MaxSlopeAngle = 0x1AC;
        inline constexpr uintptr_t MoveDirection = 0x140;
        inline constexpr uintptr_t MoveToPart = 0x118;
        inline constexpr uintptr_t MoveToPoint = 0x164;
        inline constexpr uintptr_t NameDisplayDistance = 0x1B0;
        inline constexpr uintptr_t NameOcclusion = 0x1B4;
        inline constexpr uintptr_t PlatformStand = 0x1DC;
        inline constexpr uintptr_t PlatformStatePointer = 0x4746A4F8;
        inline constexpr uintptr_t RequiresNeck = 0x1DD;
        inline constexpr uintptr_t RigType = 0x1C0;
        inline constexpr uintptr_t SeatPart = 0x108;
        inline constexpr uintptr_t Sit = 0x1DD;
        inline constexpr uintptr_t TargetPoint = 0x14C;
        inline constexpr uintptr_t UseJumpPower = 0x1E0;
        inline constexpr uintptr_t WalkTimer = 0x408;
        inline constexpr uintptr_t Walkspeed = 0x1D0;
        inline constexpr uintptr_t WalkspeedCheck = 0x3BC;
    }

    namespace Instance {
        inline constexpr uintptr_t ChildrenEnd = 0x8;
        inline constexpr uintptr_t ChildrenStart = 0x70;
        inline constexpr uintptr_t ClassBase = 0x230;
        inline constexpr uintptr_t ClassDescriptor = 0x18;
        inline constexpr uintptr_t ClassName = 0x8;
        inline constexpr uintptr_t ComponentMap = 0x38;
        inline constexpr uintptr_t Name = 0x98;
        inline constexpr uintptr_t Parent = 0x68;
        inline constexpr uintptr_t This = 0x8;
    }

    namespace Lighting {
        inline constexpr uintptr_t Ambient = 0xC8;
        inline constexpr uintptr_t Brightness = 0x110;
        inline constexpr uintptr_t ClockTime = 0x1A8;
        inline constexpr uintptr_t ColorShift_Bottom = 0xE0;
        inline constexpr uintptr_t ColorShift_Top = 0xD4;
        inline constexpr uintptr_t EnvironmentDiffuseScale = 0x114;
        inline constexpr uintptr_t EnvironmentSpecularScale = 0x118;
        inline constexpr uintptr_t ExposureCompensation = 0x11C;
        inline constexpr uintptr_t FogColor = 0xEC;
        inline constexpr uintptr_t FogEnd = 0x124;
        inline constexpr uintptr_t FogStart = 0x128;
        inline constexpr uintptr_t GeographicLatitude = 0x180;
        inline constexpr uintptr_t GlobalShadows = 0x138;
        inline constexpr uintptr_t GradientBottom = 0x184;
        inline constexpr uintptr_t GradientTop = 0x140;
        inline constexpr uintptr_t LightColor = 0x14C;
        inline constexpr uintptr_t LightDirection = 0x158;
        inline constexpr uintptr_t MoonPosition = 0x174;
        inline constexpr uintptr_t OutdoorAmbient = 0xF8;
        inline constexpr uintptr_t Sky = 0x1C8;
        inline constexpr uintptr_t Source = 0x164;
        inline constexpr uintptr_t SunPosition = 0x168;
    }

    namespace LocalScript {
        inline constexpr uintptr_t ByteCode = 0x190;
        inline constexpr uintptr_t GUID = 0xD0;
        inline constexpr uintptr_t Hash = 0x1A0;
    }

    namespace MaterialColors {
        inline constexpr uintptr_t Asphalt = 0x30;
        inline constexpr uintptr_t Basalt = 0x27;
        inline constexpr uintptr_t Brick = 0xF;
        inline constexpr uintptr_t Cobblestone = 0x33;
        inline constexpr uintptr_t Concrete = 0xC;
        inline constexpr uintptr_t CrackedLava = 0x2D;
        inline constexpr uintptr_t Glacier = 0x1B;
        inline constexpr uintptr_t Grass = 0x6;
        inline constexpr uintptr_t Ground = 0x2A;
        inline constexpr uintptr_t Ice = 0x36;
        inline constexpr uintptr_t LeafyGrass = 0x39;
        inline constexpr uintptr_t Limestone = 0x3F;
        inline constexpr uintptr_t Mud = 0x24;
        inline constexpr uintptr_t Pavement = 0x42;
        inline constexpr uintptr_t Rock = 0x18;
        inline constexpr uintptr_t Salt = 0x3C;
        inline constexpr uintptr_t Sand = 0x12;
        inline constexpr uintptr_t Sandstone = 0x21;
        inline constexpr uintptr_t Slate = 0x9;
        inline constexpr uintptr_t Snow = 0x1E;
        inline constexpr uintptr_t WoodPlanks = 0x15;
    }

    namespace MeshContentProvider {
        inline constexpr uintptr_t AssetID = 0x10;
        inline constexpr uintptr_t Cache = 0xF0;
        inline constexpr uintptr_t LRUCache = 0x20;
        inline constexpr uintptr_t MeshData = 0x40;
        inline constexpr uintptr_t ToMeshData = 0x40;
    }

    namespace MeshData {
        inline constexpr uintptr_t FaceEnd = 0x38;
        inline constexpr uintptr_t FaceStart = 0x30;
        inline constexpr uintptr_t VertexEnd = 0x8;
        inline constexpr uintptr_t VertexStart = 0x0;
    }

    namespace MeshPart {
        inline constexpr uintptr_t MeshId = 0x290;
        inline constexpr uintptr_t Texture = 0x2C0;
    }

    namespace Misc {
        inline constexpr uintptr_t Adornee = 0xF0;
        inline constexpr uintptr_t AnimationId = 0xC0;
        inline constexpr uintptr_t StringLength = 0x10;
        inline constexpr uintptr_t Value = 0xB8;
    }

    namespace Model {
        inline constexpr uintptr_t PrimaryPart = 0x258;
        inline constexpr uintptr_t Scale = 0x144;
    }

    namespace ModuleScript {
        inline constexpr uintptr_t ByteCode = 0x138;
        inline constexpr uintptr_t GUID = 0xD0;
        inline constexpr uintptr_t Hash = 0x148;
        inline constexpr uintptr_t IsCoreScript = 0x0;
    }

    namespace MouseService {
        inline constexpr uintptr_t InputObject = 0xF0;
        inline constexpr uintptr_t InputObject2 = 0x100;
        inline constexpr uintptr_t MousePosition = 0xD4;
        inline constexpr uintptr_t SensitivityPointer = 0x0;
    }

    namespace ParticleEmitter {
        inline constexpr uintptr_t Acceleration = 0x1E0;
        inline constexpr uintptr_t Brightness = 0x21C;
        inline constexpr uintptr_t Drag = 0x220;
        inline constexpr uintptr_t Lifetime = 0x1F4;
        inline constexpr uintptr_t LightEmission = 0x238;
        inline constexpr uintptr_t LightInfluence = 0x23C;
        inline constexpr uintptr_t Rate = 0x248;
        inline constexpr uintptr_t RotSpeed = 0x1FC;
        inline constexpr uintptr_t Rotation = 0x204;
        inline constexpr uintptr_t Speed = 0x20C;
        inline constexpr uintptr_t SpreadAngle = 0x214;
        inline constexpr uintptr_t Texture = 0x1C0;
        inline constexpr uintptr_t TimeScale = 0x25C;
        inline constexpr uintptr_t VelocityInheritance = 0x260;
        inline constexpr uintptr_t ZOffset = 0x264;
    }

    namespace Player {
        inline constexpr uintptr_t AccountAge = 0x35C;
        inline constexpr uintptr_t CameraMode = 0x370;
        inline constexpr uintptr_t DisplayName = 0x138;
        inline constexpr uintptr_t HealthDisplayDistance = 0x390;
        inline constexpr uintptr_t LocalPlayer = 0x130;
        inline constexpr uintptr_t LocaleId = 0x118;
        inline constexpr uintptr_t MaxZoomDistance = 0x368;
        inline constexpr uintptr_t MinZoomDistance = 0x36C;
        inline constexpr uintptr_t ModelInstance = 0x298;
        inline constexpr uintptr_t Mouse = 0x11D8;
        inline constexpr uintptr_t NameDisplayDistance = 0x3A0;
        inline constexpr uintptr_t Team = 0x2D8;
        inline constexpr uintptr_t TeamColor = 0x3AC;
        inline constexpr uintptr_t UserId = 0x300;
    }

    namespace PlayerConfigurer {
        inline constexpr uintptr_t Pointer = 0x0;
    }

    namespace PlayerMouse {
        inline constexpr uintptr_t Icon = 0xC8;
        inline constexpr uintptr_t Workspace = 0x150;
    }

    namespace Primitive {
        inline constexpr uintptr_t AssemblyAngularVelocity = 0x104;
        inline constexpr uintptr_t AssemblyLinearVelocity = 0xF8;
        inline constexpr uintptr_t Flags = 0x1B6;
        inline constexpr uintptr_t Material = 0x0;
        inline constexpr uintptr_t Owner = 0x208;
        inline constexpr uintptr_t Position = 0xEC;
        inline constexpr uintptr_t Rotation = 0xC8;
        inline constexpr uintptr_t Size = 0x1B8;
        inline constexpr uintptr_t Validate = 0x6;
    }

    namespace PrimitiveFlags {
        inline constexpr uintptr_t Anchored = 0x2;
        inline constexpr uintptr_t CanCollide = 0x8;
        inline constexpr uintptr_t CanQuery = 0x20;
        inline constexpr uintptr_t CanTouch = 0x10;
    }

    namespace ProximityPrompt {
        inline constexpr uintptr_t ActionText = 0xB0;
        inline constexpr uintptr_t Enabled = 0x136;
        inline constexpr uintptr_t GamepadKeyCode = 0x11C;
        inline constexpr uintptr_t HoldDuration = 0x120;
        inline constexpr uintptr_t KeyCode = 0x124;
        inline constexpr uintptr_t MaxActivationDistance = 0x128;
        inline constexpr uintptr_t ObjectText = 0xD0;
        inline constexpr uintptr_t RequiresLineOfSight = 0x137;
    }

    namespace RenderJob {
        inline constexpr uintptr_t FakeDataModel = 0x38;
        inline constexpr uintptr_t RealDataModel = 0x1C8;
        inline constexpr uintptr_t RenderView = 0x1D0;
    }

    namespace RenderView {
        inline constexpr uintptr_t DeviceD3D11 = 0x8;
        inline constexpr uintptr_t LightingValid = 0x150;
        inline constexpr uintptr_t SkyValid = 0x28D;
        inline constexpr uintptr_t VisualEngine = 0x10;
    }

    namespace RunService {
        inline constexpr uintptr_t HeartbeatFPS = 0xB4;
        inline constexpr uintptr_t HeartbeatTask = 0xC08;
    }

    namespace Script {
        inline constexpr uintptr_t ByteCode = 0x190;
        inline constexpr uintptr_t GUID = 0xD0;
        inline constexpr uintptr_t Hash = 0x1A0;
    }

    namespace ScriptContext {
        inline constexpr uintptr_t RequireBypass = 0x0;
    }

    namespace Seat {
        inline constexpr uintptr_t Occupant = 0x1B0;
    }

    namespace Sky {
        inline constexpr uintptr_t MoonAngularSize = 0x244;
        inline constexpr uintptr_t MoonTextureId = 0xC8;
        inline constexpr uintptr_t SkyboxBk = 0xF8;
        inline constexpr uintptr_t SkyboxDn = 0x128;
        inline constexpr uintptr_t SkyboxFt = 0x158;
        inline constexpr uintptr_t SkyboxLf = 0x188;
        inline constexpr uintptr_t SkyboxOrientation = 0x238;
        inline constexpr uintptr_t SkyboxRt = 0x1B8;
        inline constexpr uintptr_t SkyboxUp = 0x1E8;
        inline constexpr uintptr_t StarCount = 0x248;
        inline constexpr uintptr_t SunAngularSize = 0x23C;
        inline constexpr uintptr_t SunTextureId = 0x218;
    }

    namespace Sound {
        inline constexpr uintptr_t Looped = 0x13D;
        inline constexpr uintptr_t PlaybackSpeed = 0x11C;
        inline constexpr uintptr_t RollOffMaxDistance = 0x120;
        inline constexpr uintptr_t RollOffMinDistance = 0x124;
        inline constexpr uintptr_t SoundGroup = 0xE8;
        inline constexpr uintptr_t SoundId = 0xC8;
        inline constexpr uintptr_t Volume = 0x130;
    }

    namespace SpawnLocation {
        inline constexpr uintptr_t AllowTeamChangeOnTouch = 0x3D;
        inline constexpr uintptr_t Enabled = 0x189;
        inline constexpr uintptr_t ForcefieldDuration = 0x180;
        inline constexpr uintptr_t Neutral = 0x18A;
        inline constexpr uintptr_t TeamColor = 0x184;
    }

    namespace SpecialMesh {
        inline constexpr uintptr_t MeshId = 0xF8;
        inline constexpr uintptr_t Scale = 0xC4;
    }

    namespace StatsItem {
        inline constexpr uintptr_t Value = 0xC8;
    }

    namespace SunRaysEffect {
        inline constexpr uintptr_t Enabled = 0xB0;
        inline constexpr uintptr_t Intensity = 0xB8;
        inline constexpr uintptr_t Spread = 0xBC;
    }

    namespace SurfaceAppearance {
        inline constexpr uintptr_t AlphaMode = 0x288;
        inline constexpr uintptr_t Color = 0x270;
        inline constexpr uintptr_t ColorMap = 0xC8;
        inline constexpr uintptr_t EmissiveMaskContent = 0xF8;
        inline constexpr uintptr_t EmissiveStrength = 0x28C;
        inline constexpr uintptr_t EmissiveTint = 0x27C;
        inline constexpr uintptr_t MetalnessMap = 0x128;
        inline constexpr uintptr_t NormalMap = 0x158;
        inline constexpr uintptr_t RoughnessMap = 0x188;
    }

    namespace TaskScheduler {
        inline constexpr uintptr_t JobEnd = 0xD0;
        inline constexpr uintptr_t JobName = 0x18;
        inline constexpr uintptr_t JobStart = 0xC8;
        inline constexpr uintptr_t MaxFPS = 0xB0;
        inline constexpr uintptr_t Pointer = 0x8041EC8;
    }

    namespace Team {
        inline constexpr uintptr_t BrickColor = 0xB8;
    }

    namespace Terrain {
        inline constexpr uintptr_t GrassLength = 0x188;
        inline constexpr uintptr_t MaterialColors = 0x438;
        inline constexpr uintptr_t WaterColor = 0x178;
        inline constexpr uintptr_t WaterReflectance = 0x190;
        inline constexpr uintptr_t WaterTransparency = 0x194;
        inline constexpr uintptr_t WaterWaveSize = 0x198;
        inline constexpr uintptr_t WaterWaveSpeed = 0x19C;
    }

    namespace Textures {
        inline constexpr uintptr_t Decal_Texture = 0x180;
        inline constexpr uintptr_t Texture_Texture = 0x180;
    }

    namespace Tool {
        inline constexpr uintptr_t CanBeDropped = 0x4B8;
        inline constexpr uintptr_t Enabled = 0x4B9;
        inline constexpr uintptr_t Grip = 0x4AC;
        inline constexpr uintptr_t ManualActivationOnly = 0x4BA;
        inline constexpr uintptr_t RequiresHandle = 0x4BB;
        inline constexpr uintptr_t TextureId = 0x360;
        inline constexpr uintptr_t Tooltip = 0x468;
    }

    namespace UnionOperation {
        inline constexpr uintptr_t AssetId = 0x288;
    }

    namespace UserInputService {
        inline constexpr uintptr_t WindowInputState = 0x2C0;
    }

    namespace VehicleSeat {
        inline constexpr uintptr_t MaxSpeed = 0x1C8;
        inline constexpr uintptr_t SteerFloat = 0x1D0;
        inline constexpr uintptr_t ThrottleFloat = 0x1D8;
        inline constexpr uintptr_t Torque = 0x1DC;
        inline constexpr uintptr_t TurnSpeed = 0x1E0;
    }

    namespace VisualEngine {
        inline constexpr uintptr_t Dimensions = 0xAB0;
        inline constexpr uintptr_t FakeDataModel = 0xA90;
        inline constexpr uintptr_t Pointer = 0x81D61C8;
        inline constexpr uintptr_t RenderView = 0xBB8;
        inline constexpr uintptr_t ViewMatrix = 0x150;
    }

    namespace Weld {
        inline constexpr uintptr_t Part0 = 0x118;
        inline constexpr uintptr_t Part1 = 0x128;
    }

    namespace WeldConstraint {
        inline constexpr uintptr_t Part0 = 0xB8;
        inline constexpr uintptr_t Part1 = 0xC8;
    }

    namespace WindowInputState {
        inline constexpr uintptr_t CapsLock = 0x40;
        inline constexpr uintptr_t CurrentTextBox = 0x48;
    }

    namespace Workspace {
        inline constexpr uintptr_t CurrentCamera = 0x488;
        inline constexpr uintptr_t DistributedGameTime = 0x4A8;
        inline constexpr uintptr_t ReadOnlyGravity = 0x998;
        inline constexpr uintptr_t World = 0x3E0;
    }

    namespace Players {
        inline constexpr uintptr_t LocalPlayer = 0x130;
    }

    namespace World {
        inline constexpr uintptr_t AirProperties = 0x218;
        inline constexpr uintptr_t FallenPartsDestroyHeight = 0x208;
        inline constexpr uintptr_t Gravity = 0x210;
        inline constexpr uintptr_t Primitives = 0x288;
        inline constexpr uintptr_t worldStepsPerSec = 0x680;
    }

} // namespace offsets
// clang-format on
