using System;
using Godot;

namespace GroundDemo.Mob.Services;

public partial class CameraManager : Node3D
{
	private Node3D _cameraPitch = null!;

	public override void _Ready()
	{
		_cameraPitch = GetNode<Node3D>("Arm");
		Input.MouseMode = Input.MouseModeEnum.Captured;
	}

	public override void _Input(InputEvent @event)
	{
		if (@event is InputEventMouseMotion mm && Input.MouseMode == Input.MouseModeEnum.Captured)
		{
			RotateCamera(mm.Relative);
			GetViewport().SetInputAsHandled();
		}
	}

	private void RotateCamera(Vector2 relative)
	{
		// Yaw (horizontal)
		var yawRot = this.Rotation;
		yawRot.Y -= relative.X * MobConstants.MouseSensitivity;
		this.Rotation = yawRot;

		// Orthonormalize the transform (whatever it means)
		this.Transform = this.Transform.Orthonormalized();

		// Pitch (vertical)
		var pitchRot = _cameraPitch.Rotation;
		pitchRot.X += relative.Y * MobConstants.MouseSensitivity * MobConstants.CameraRatio * MobConstants.MouseYInversion;
		pitchRot.X = Mathf.Clamp(pitchRot.X, MobConstants.CameraMinPitch, MobConstants.CameraMaxPitch);
		_cameraPitch.Rotation = pitchRot;
	}
}
