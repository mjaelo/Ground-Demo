using Godot;

namespace GroundDemo.Mob.Scenes.Mobs.Npc;

public partial class Npc : CharacterBody3D
{
	// vars set by MobActivationManager
	public Node3D? Target;
	public bool NavigationReady = false;

	// private vars
	private NavigationAgent3D _navAgent = null!;
	private float _retargetTimer = 1.0f;

	public override void _Ready()
	{
		_navAgent = GetNode<NavigationAgent3D>("NavigationAgent3D");
		_navAgent.VelocityComputed += safeVelocity =>
		{
			// apply only horizontal components from computed safe velocity
			Velocity = new Vector3(safeVelocity.X, Velocity.Y, safeVelocity.Z);
			MoveAndSlide();
		};
	}

	public override void _Process(double delta)
	{
		if (!NavigationReady)
		{
			return;
		}

		_retargetTimer += (float)delta;
		if (Target == null || _retargetTimer <= MobConstants.RetargetCooldown)
		{
			return;
		}

		_retargetTimer = 0.0f;
		_navAgent.SetTargetPosition(Target.GlobalPosition);
	}

	public override void _PhysicsProcess(double delta)
	{
		if (!NavigationReady) return;

		float yVel = Velocity.Y - MobConstants.NpcGravity * (float)delta;

		if (Target == null || _navAgent.IsNavigationFinished())
		{
			Velocity = new Vector3(0, yVel, 0);
		}
		else
		{
			var nextPos = _navAgent.GetNextPathPosition();
			var currentPos = GlobalPosition;
			Vector3 dir;

			if (nextPos.DistanceSquaredTo(currentPos) < 1.0f)
			{
				dir = Target.GlobalPosition - currentPos;
				dir.Y = 0.0f;
				dir = dir.Normalized();
			}
			else
			{
				dir = (nextPos - currentPos).Normalized();
			}

			Velocity = new Vector3(dir.X * MobConstants.NpcMoveSpeed, yVel, dir.Z * MobConstants.NpcMoveSpeed);
		}

		if (_navAgent.AvoidanceEnabled) _navAgent.SetVelocity(Velocity);
		else MoveAndSlide();
	}
}
