# TrainingDummy.gd - 训练假人
# 在训练场中使用，可配置行为模式
extends Fighter
class_name TrainingDummy

enum DummyMode {
	STAND,       # 站立不动
	CROUCH,      # 一直蹲着
	WALK,        # 来回走动
	BLOCK_ALL,   # 防御所有攻击
	RANDOM,      # 随机行动
}

signal dummy_mode_changed(new_mode: DummyMode)

@export var dummy_mode: DummyMode = DummyMode.STAND
var _walk_direction := 1
var _action_timer := 0.0
var _random_timer := 0.0
var _spawn_position := Vector2.ZERO


func _ready() -> void:
	super._ready()
	player_id = 2
	health = GlobalConfig.MAX_HEALTH
	meter = GlobalConfig.MAX_METER
	_spawn_position = position


func _physics_process(delta: float) -> void:
	state_time += 1
	
	match dummy_mode:
		DummyMode.STAND:
			_do_stand()
		DummyMode.CROUCH:
			_do_crouch()
		DummyMode.WALK:
			_do_walk(delta)
		DummyMode.BLOCK_ALL:
			_do_block_all()
		DummyMode.RANDOM:
			_do_random(delta)
	
	if not _is_grounded():
		velocity.y += gravity * delta
	
	move_and_slide()
	_update_facing()
	
	# 训练模式: 自动回血回气
	if MatchData.current_mode == MatchData.GameMode.TRAINING:
		if MatchData.training_health_infinite and health < GlobalConfig.MAX_HEALTH:
			health = GlobalConfig.MAX_HEALTH
		if MatchData.training_meter_infinite:
			meter = GlobalConfig.MAX_METER


func _do_stand() -> void:
	velocity.x = 0
	current_state = FighterState.State.IDLE


func _do_crouch() -> void:
	velocity.x = 0
	current_state = FighterState.State.CROUCH


func _do_walk(delta: float) -> void:
	_action_timer -= delta
	if _action_timer <= 0:
		_walk_direction *= -1
		_action_timer = 2.0
	velocity.x = GlobalConfig.WALK_SPEED * 0.5 * _walk_direction
	current_state = FighterState.State.WALK_FORWARD


func _do_block_all() -> void:
	velocity.x = 0
	current_state = FighterState.State.STAND_BLOCK


func _do_random(delta: float) -> void:
	_random_timer -= delta
	if _random_timer <= 0:
		_random_timer = randf_range(1.0, 3.0)
		var states := [
			FighterState.State.IDLE,
			FighterState.State.IDLE,
			FighterState.State.CROUCH,
			FighterState.State.WALK_FORWARD,
		]
		current_state = states[randi() % states.size()]


# 由训练场控制器调用: 切换假人行为模式
func set_dummy_mode(mode: DummyMode) -> void:
	if dummy_mode != mode:
		dummy_mode = mode
		dummy_mode_changed.emit(mode)


# 由训练场控制器调用: 将假人复位到初始状态
func reset_dummy() -> void:
	health = GlobalConfig.MAX_HEALTH
	meter = GlobalConfig.MAX_METER
	velocity = Vector2.ZERO
	position = _spawn_position
	current_state = FighterState.State.IDLE
	health_changed.emit(health, GlobalConfig.MAX_HEALTH)
	meter_changed.emit(meter, GlobalConfig.MAX_METER)
