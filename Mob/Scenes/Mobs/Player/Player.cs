using Godot;
using GroundDemo.Ground;

namespace GroundDemo.Mob.Scenes.Mobs.Player;

public partial class Player : CharacterBody3D
{
	public float MoveSpeed = MobConstants.PlayerMoveSpeed;
	
	// cached nodes
	private Camera3D _camera = null!;
	private SpringArm3D _arm = null!;
	private MeshInstance3D _body = null!;
	private CollisionShape3D _collisionShapeBody = null!;
	private CollisionShape3D _collisionShapeRay = null!;

	private bool _isFirstPerson;
	private bool _isCollisionEnabled;
	private bool _isGravityEnabled;
	private Tween? _fpsTween;

	public override void _Ready()
	{
		// cache nodes from the scene
		_arm = GetNode<SpringArm3D>("CameraManager/Arm");
		_camera = GetNode<Camera3D>("CameraManager/Arm/Camera3D");
		_body = GetNode<MeshInstance3D>("Body");
		_collisionShapeBody = GetNode<CollisionShape3D>("CollisionShapeBody");
		_collisionShapeRay = GetNode<CollisionShape3D>("CollisionShapeRay");
	}

	public void Init()
	{
		SetGravityEnabled(false);
		SetCollisionEnabled(false);
		SetPhysicsProcess(false);
	}

	public override void _PhysicsProcess(double delta)
	{
		Vector3 direction = GetCameraRelativeInput();
		Vector2 hDir = new(direction.X, direction.Z);
		Vector2 hVeloc = (hDir.LengthSquared() > 0f ? hDir.Normalized() : hDir) * MoveSpeed;
		if (Input.IsKeyPressed(Key.Shift)) hVeloc *= 10.0f;

		float yVel = Velocity.Y;
		float thrust = MobConstants.JumpSpeed + MoveSpeed * (float)delta;
		if (Input.IsKeyPressed(Key.Space)) yVel += thrust;
		if (Input.IsKeyPressed(Key.Q)) yVel -= thrust;

		if (GlobalPosition.Y < GroundConstants.WaterSurfaceLevel - 1.0f)
			yVel += 30.0f * (float)delta;
		else if (_isGravityEnabled)
			yVel -= 40.0f * (float)delta;

		Velocity = new Vector3(hVeloc.X, yVel, hVeloc.Y);
		MoveAndSlide();
	}
	
	// bool setters
	private void SetFirstPerson(bool value)
	{
		if (value == _isFirstPerson) return;
		_isFirstPerson = value;
		_fpsTween?.Kill();
		_fpsTween = CreateTween();
		if (_isFirstPerson)
		{
			_fpsTween.TweenProperty(_arm, "spring_length", 0.0f, 0.33f);
			_fpsTween.TweenCallback(Callable.From(() => _body.Visible = false));
		}
		else
		{
			_body.Visible = true;
			_fpsTween.TweenProperty(_arm, "spring_length", 6.0f, 0.33f);
		}
	}

	public void   SetGravityEnabled(bool value)
	{
		if (value == _isGravityEnabled) return;
		_isGravityEnabled = value;
		if (!_isGravityEnabled)
		{
			Velocity = new Vector3(Velocity.X, 0.0f, Velocity.Z);
		}
	}
	 
	public void  SetCollisionEnabled(bool value)
	{
		if (value == _isCollisionEnabled) return;
		_isCollisionEnabled = value;
		_collisionShapeBody.Disabled = !_isCollisionEnabled;
		_collisionShapeRay.Disabled = !_isCollisionEnabled;
	}
	
	
	// Returns the input vector relative to the camera. Forward is always the direction the camera is facing
	private Vector3 GetCameraRelativeInput()
	{
		var inputDir = Vector3.Zero;
		Basis basis = _camera.GlobalTransform.Basis;

		if (Input.IsKeyPressed(Key.A)) inputDir -= basis.X;
		if (Input.IsKeyPressed(Key.D)) inputDir += basis.X;
		if (Input.IsKeyPressed(Key.W)) inputDir -= basis.Z;
		if (Input.IsKeyPressed(Key.S)) inputDir += basis.Z;

		return inputDir;
	}

	public override void _Input(InputEvent @event)
	{
		switch (@event)
		{
			case InputEventMouseButton { Pressed: true, ButtonIndex: MouseButton.WheelUp }:
				MoveSpeed = Mathf.Clamp(MoveSpeed + 5.0f, 5.0f, 9999.0f);
				break;
			case InputEventMouseButton { Pressed: true } mb:
			{
				if (mb.ButtonIndex == MouseButton.WheelDown)
					MoveSpeed = Mathf.Clamp(MoveSpeed - 5.0f, 5.0f, 9999.0f);
				break;
			}
			case InputEventKey { Pressed: true } kv:
			{
				switch (kv.Keycode)
				{
					case Key.V:
						SetFirstPerson(!_isFirstPerson);
						break;
					case Key.G:
						SetGravityEnabled(!_isGravityEnabled);
						break;
					case Key.C:
						SetCollisionEnabled(!_isCollisionEnabled);
						break;
				}

				break;
			}
			case InputEventKey kv:
			{
				// release of up/down keys stops vertical velocity
				if (kv.Keycode is Key.Q or Key.E or Key.Space)
					Velocity = new Vector3(Velocity.X, 0.0f, Velocity.Z);
				break;
			}
		}
	}
}
