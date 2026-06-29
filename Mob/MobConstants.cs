using System;

namespace GroundDemo.Mob;

public static class MobConstants
{
    // NPC
    public const float NpcMoveSpeed = 40.0f;
    public const float RetargetCooldown = 1.0f;
    /// Gravity acceleration applied to NPCs each second (m/s²).
    public const float NpcGravity = 40.0f;
    
    // PLAYER
    public const float PlayerMoveSpeed = 50.0f;
    public const float JumpSpeed = 2.0f;

    // CAMERA
    public const float CameraMaxPitch = 70.0f * (MathF.PI / 180.0f); // 70 degrees in radians
    public const float CameraMinPitch = -89.9f * (MathF.PI / 180.0f); // -89.9 degrees in radians
    public const float CameraRatio = 0.625f;
    public const float MouseSensitivity = 0.002f;
    public const float MouseYInversion = -1.0f;
}