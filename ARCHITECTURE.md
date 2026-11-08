# 2D横版格斗游戏 - 项目架构说明

## 项目结构

```
FightingGame/
├── project.godot              # Godot项目配置(输入映射、自动加载等)
├── icon.png                   # 游戏图标(占位)
│
├── scenes/                    # 场景文件(.tscn)
│   ├── menu/
│   │   ├── main_menu.tscn     # 主菜单: 本地对战/训练场/设置/画廊/退出
│   │   ├── settings.tscn      # 设置界面
│   │   └── gallery.tscn       # 画廊界面
│   ├── select/
│   │   └── character_select.tscn  # 角色选择: 网格+立绘+颜色
│   └── versus/
│       └── versus_battle.tscn # 对战场景: 场地+角色+HUD
│
├── scripts/                   # GDScript脚本
│   ├── autoload/              # 全局单例(自动加载)
│   │   ├── global_config.gd   # 全局配置: 血量/速度/重力/音量等常量
│   │   ├── input_handler.gd   # 输入处理: 双人键位/8帧缓冲/24帧指令历史/数字方向
│   │   ├── audio_manager.gd   # 音频管理: BGM/SFX播放+渐变
│   │   └── match_data.gd      # 比赛数据: 角色列表/选择/模式/结果
│   ├── menu/
│   │   ├── main_menu.gd       # 主菜单逻辑
│   │   ├── settings.gd        # 设置逻辑(占位)
│   │   └── gallery.gd         # 画廊逻辑(占位)
│   ├── select/
│   │   └── character_select.gd # 选人逻辑: 双人独立操作
│   ├── versus/
│   │   ├── fighter.gd         # ★核心: 格斗角色控制器
│   │   ├── fighter_state.gd   # 状态枚举: 28种格斗状态
│   │   ├── attack_data.gd     # 攻击数据资源: 伤害/帧数/判定
│   │   ├── hitbox.gd          # 攻击判定框
│   │   ├── hurtbox.gd         # 受击判定框
│   │   ├── battle_camera.gd   # 战斗摄像机: 双向缩放/纵向拟合/受击方优先/边框限制
│   │   ├── round_manager.gd   # 回合管理: 倒计时/胜负/三局两胜
│   │   ├── combo_tracker.gd   # 连击计数: 受击硬直内累计/结束后1秒纯显示(纯逻辑)
│   │   ├── versus_battle.gd   # 对战场景主控制器
│   │   └── training_dummy.gd  # 训练假人AI
│   └── hud/
│       └── battle_hud.gd      # 对战HUD: 血量/气槽/计时器/连击
│
└── resources/                 # 资源文件
    ├── characters/
    │   ├── default_fighter.tscn          # 默认角色模板(招式数组见第 2、13 节)
    │   └── default_training_dummy.tscn   # 训练假人模板
    └── effects/
        └── hit_spark.tscn                 # 命中火花
```

> 对战场地(地面/墙)由 `VersusBattle._setup_arena()` 在代码中生成，暂无独立 `.tscn` 资源。

## 核心系统

### 1. 状态机 (FighterState)

角色共有 **28种状态**，按类别分为:

- **移动类**: IDLE / WALK_FORWARD / WALK_BACK / DASH_FORWARD / DASH_BACK / CROUCH
- **跳跃类**: JUMP_UP / JUMP_FORWARD / JUMP_BACK
- **防御类**: STAND_BLOCK / CROUCH_BLOCK
- **攻击类**: ATTACK_LIGHT / ATTACK_MEDIUM / ATTACK_HEAVY / ATTACK_SPECIAL / GRAB
- **受击类**: HIT_STUN / GRABBED / KNOCKDOWN / LIEDOWN / TECH / SOFT_KNOCKDOWN / WAKEUP
- **系统类**: ESCAPE (脱离) / CRASHED (相杀)
- **演出类**: INTRO / VICTORY / DEFEATED

### 2. 攻击系统 (AttackData)

一招攻击由若干**段**(Segment)组成，每段有独立的帧数据、判定框几何与命中结算：

- `trigger_frame`(触发帧) + `active_duration`(持续帧)；招式总帧数 = 所有段 `(trigger + active)` 的最大值。
- 段字段：防御属性(`DefenseProperty`：FULL_BLOCK / STANCE_BREAK / CROUCH_BREAK / UNBLOCKABLE / GRAB_BREAK_REQUIRED)、攻击属性位标志(`AttackAttribute`：抓取 / 飞行道具 / 气攻等)、伤害·硬直·削血·击退·强制倒地、甜点·酸点区域。
- **招式数组**(角色差异化)：`light_attacks` / `medium_attacks` / `heavy_attacks`(通常技)、`special_attacks`(必杀技，默认空)；空中另有 6 组 `air_*` 数组(见第 8、13 节)。
- **取消链**：通常技(轻/中/重) → 必杀技(236/214/623 + A/B/C，链尾)。**不再有 轻→中→重 链**；A+B / B+C 已改为抓取 / 格挡技组合输入。
- 命中结算支持防御 / 拆投 / 削血 / 虚血 / 浮空追击 / 相杀 / 版边反弹；`Segment` 是 `RefCounted`，深拷贝必须走 `duplicate_segment()`(见第 8 节)。

### 3. 输入系统 (InputHandler)

- 双人独立输入：方向 + 六个动作键 **A/B/C/D/E/F** + START；默认键位见文末「按键映射」。每个动作默认只绑定**一枚主键**，2P 也不再提供「无小键盘时」的主键盘副键。
- 键位可在设置界面重绑定，持久化到 `user://input.cfg`（自定义优先于默认值）。
- 数字方向(小键盘记法 1~9，5=中立)；指令识别使用**朝向相对**方向(6 始终 = 朝对手，角色朝左时屏幕方向自动水平翻转)。
- **8 帧按钮输入缓冲**(取消窗口) 与 **24 帧指令识别方向历史**(`MOTION_HISTORY_FRAMES`)分离：半圈 / 升龙按人类出招速度约需 9~15 帧，8 帧装不下(详见第 11 节)。

### 4. 对战系统 (RoundManager)

- 三局两胜制
- 99秒倒计时，超时按血量判定
- 每回合重置位置和血量

### 5. 版边系统 (Wall Bounce / Wall Jump)

版边=**墙固定在舞台边缘**（x ∈ [FIGHTER_BOUND_MARGIN, STAGE_WIDTH−FIGHTER_BOUND_MARGIN]，即 [40, 1880]），与摄像机画面边框相互独立。

- **版边反弹**（`Fighter._clamp_to_stage` → `_try_wall_bounce`）：受击（HIT_STUN）滑行撞墙时，按 `WALL_BOUNCE_RETENTION`（默认0.5）保留比例反射入射速度；**不追加伤害/虚血，不改变硬直**（继续受击硬直，可构成墙边连段）；入射低于 `WALL_BOUNCE_MIN_SPEED` 仅贴墙不反弹。触发时发 `wall_bounced` 信号，由 versus_battle 驱动火花+震屏演出。
- **蹬墙跳**（`Fighter._process_jump` → `_try_wall_jump`）：空中贴近版边（`WALL_JUMP_RANGE`）按跳跃键，朝墙外弹出；**每次离地限一次**（落地/回中立重置）；前后方向键影响距离（远离墙 ×1.3 / 朝向墙 ×0.6 / 不按 ×1.0）。地面起跳仍是普通跳跃，不受影响。

### 6. 战斗摄像机 (BattleCamera)

挂载于 versus_battle.tscn 的 Camera2D 节点，由 versus_battle.gd 每帧驱动 `update_camera(delta)`；震屏仍由 versus_battle 写 `camera.offset`（与位置/缩放独立）。

- **横向缩放**：双方贴身 → 放大至 `CAM_MAX_ZOOM_IN`（1.25）；拉开 → 扩放至 `CAM_MIN_ZOOM`（0.9，上限）。
- **纵向拟合**：只要未进入受击方优先模式（含**攻击方在地面、受击方在空中**的受击情况——此时扩放框住双方，不冻结），若有人跳高出画面上边界，继续压缩放框住双方视觉包围盒（同一 0.9 下限；镜头允许高出舞台顶部，底部不露舞台底）。
- **受击方优先**：双方均离地且恰好一方受击 → 中心钉受击方、缩放冻结；攻击方移动出画面不触发任何扩放。
- **画面边框限制**：已最大扩放且双方间距超过帧宽时，把双方钳制在 **帧边缘∩墙边界**（取更严者）。用目标帧（非平滑帧）判定，不会截断冲刺；只钳位置不改速度。

### 7. 倒地/受身/起身系统 (Knockdown → LIEDOWN → TECH/WAKEUP)

击飞命中（`causes_knockdown`）走完整倒地流程；软倒地（被追地命中）保持短硬直后自行起身，**不进入受身流程**。

```
KNOCKDOWN(击飞滑行) --落地--> LIEDOWN(躺地)
                                |
  受身窗口 12 帧内按方向 --------> TECH(受身: 朝方向翻滚 260px/s, 全程无敌 16 帧, 18 帧后回中立)
                                |
  窗口外按方向 ------------------> WAKEUP(带方向起身: 前/后各位移 50px, 26 帧)
                                |
  躺地 30 帧无输入 --------------> WAKEUP(原地起身, 20 帧)
```

- 方向均以**面朝对手为前**（`_direction_toward_opponent()`）：前/后受身与起身速度/位移按此换算；下方向键等同"有输入"（原地受身/起身）。
- 受身无敌帧在 `_on_hit`/`_begin_grabbed` 入口统一拦截（`invincible_frames > 0` 直接 return），落地/起身清零。
- 全部数值在 `global_config.gd` 的 `TECH_*`/`LIEDOWN_AUTO_WAKEUP_FRAMES`/`WAKEUP_*` 常量中，标注"设计值可调"。

### 8. 空中通常技 (JA/JB/JC)

- 空中 A/B/C 对应 `air_light_attacks` / `air_medium_attacks` / `air_heavy_attacks`；D / E / 必杀指令在空中由三个**可选模块**接管(见第 13 节)。模板默认这些数组为空，因此默认行为仍是「空中 D/E 无效、指令 + A/B/C 退化为空中通常技」(`_handle_attack_input(airborne := true)`)。
- 招式数据默认由地面同键位攻击**深拷贝微调**生成（`air_*_attacks` 数组，角色差异化数据到位后直接覆盖即可）：
  - 出招帧 +1（`AIR_ATTACK_TRIGGER_DELAY`），判定框纵向 ×0.8（`AIR_ATTACK_SIZE_MULT`）；
  - 伤害/击退/硬直等沿用地面版，起跳惯性保留（空中攻击不清零速度）。
- 深拷贝必须显式处理段数组：`Segment` 是 RefCounted，`Resource.duplicate(true)` **不会**带上 `segments`，且共享段对象会让空中微调污染地面版数据；故用 `AttackData.Segment.duplicate_segment()` 逐段拷贝后整体赋值（见 `attack_data.gd` 与 `fighter.gd` 的空中攻击构建段）。

### 9. 冲刺 (Dash) 双击识别

- 双击识别（`_check_dash_input`）**先于行走判定**执行（`_handle_universal_input` 内顺序保证），避免单击后误入行走导致双击丢识别。
- `buffer_timer` 每次按方向置 `DASH_BUFFER_FRAMES`（**8 帧**）并逐帧递减：窗口内第二次同方向 = 冲刺；窗口过期后重新单击 = 正常行走（冒烟测试覆盖：单击行走/缓冲过期不冲/双击前后冲刺/8 帧窗口边界）。它与 `InputHandler.INPUT_BUFFER`（8 帧按钮取消缓冲）数值相同但语义独立，分别调整互不影响。

### 10. 判定框生命周期注意事项 (Hitbox)

- `Hitbox.deactivate()` 失效时会把碰撞形状挪到远处（`shape_node.position = (100000, 0)`），而非仅置 `monitoring = false`：Area2D 监视是单向持续注册的，形状留在原处会让对方受击框保持"已进入"而不产生退出事件，导致下次激活恢复几何时**不再触发 `area_entered`，命中被静默漏掉**（第二段及以后全部丢判定）。
- 不要用 `CollisionShape2D.disabled` 切换（运行时重新启用不会与已有监视者重配）或 `monitorable` 切换（物理服务器重配监视对有延迟，进入信号会晚于判定框失效到达，同样漏命中）。
- 角色 `.tscn` 中的判定框/受击框形状子资源必须 `resource_local_to_scene = true`：否则多实例共享同一 `RectangleShape2D`，`_apply_segment()` 改写 `extents` 会互相污染。

### 11. 必杀技指令识别 (QCF 236 / QCB 214 / DP 623)

指令识别基于**朝向相对**数字方向（6=朝对手；角色朝左时屏幕方向自动水平翻转，`_flip_numpad_horizontal`），在 `InputHandler` 的 24 帧指令历史（`MOTION_HISTORY_FRAMES`，与 8 帧按钮取消缓冲分离）中做**子序列匹配**；同时命中多个指令时取匹配结束最晚者（输入意图最新）。

| 指令 | 输入 | 映射下标(地面 `special_attacks` / 空中 `air_special_attacks`) |
| ---- | ---- | ---- |
| QCF 236 | 下(2)→下前(3)→前(6) | [0] |
| QCB 214 | 下(2)→下后(1)→后(4) | [1] |
| DP 623 | 前(6)→下(2)→下前(3) | [2] |

- **招式数据由用户自行管理**：每个角色的必杀技是不同的招式，本仓库只做指令识别与下标映射，**不预置任何必杀技数据**（`special_attacks` 默认为空）。角色(或用户)向 `special_attacks` 追加自己的招式数据，对应指令即刻生效；**没有数据的指令不触发**，自然退化为通常技（`_recognized_special_index` 跳过越界下标）。
- **空中必杀**复用同一套指令与朝向相对识别（`_recognized_air_special_index`），映射到独立的 `air_special_attacks`（见第 13 节）；地面 / 空中数组互不影响，没有数据的指令同样不触发而退化为空中通常技。
- **触发键**：指令 + A/B/C 任一攻击键（招式由指令区分，不由按键区分）；乱序/滑出窗口(>24帧)不识别。
- **起手与取消**均可触发（取消过第一段触发帧后，`_check_cancel_input`）；成功后 `clear_motion_history` **消耗**指令历史，防止同一次输入重复触发。
- 击飞类招式（段 `causes_knockdown`）命中站地上的对手时，`_process_knockdown` 有 2 帧保护且上升中(`velocity.y < 0`)不判落地——否则起跳当帧 `is_on_floor()` 的旧值 `true` 会把击飞升空误判为已落地，直接跳进躺地。

### 12. 连击计数器 (ComboTracker)

> **1 秒 = 连击结束后计数器显示连击数的持续时间，仅此而已。** 它不是记录窗口，也没有容差、续连、宽限等额外语义：记录判定完全不参考这 1 秒，滞留期间发生的命中一律按**新连击**处理（从 1 开始），旧的显示计时随即作废。

| 环节   | 规则                                                                                                                                                                                                                               |
| ---- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 显示位置 | **攻击方**血量条正下方（`P1Side/ComboLabel` / `P2Side/ComboLabel`），双方各自独立；气槽与回合指示为这一行下移腾出空间                                                                                                                                                |
| 记录范围 | **仅限对方处于受击硬直**（`FighterState.RESTRICTED_STATES`：HIT_STUN / GRABBED / KNOCKDOWN / LIEDOWN / TECH / SOFT_KNOCKDOWN / WAKEUP / CRASHED，即被命中后不能自由活动）的时间。范围内每次**有效命中（非格挡）**累加到同一连击，**≥1 hit 即显示**（`1 HIT` / `N HITS`），命中当帧实时刷新 |
| 连击结束 | 对方一旦恢复自由活动（防御/走动/攻击/回合流程状态），**记录立即重置**（`count=0`，最后数字存入 `last_count`）；HUD 保留该数字**显示 1 秒**（`GlobalConfig.COMBO_LINGER_SECONDS`）后隐藏。这 1 秒只驱动标签隐藏，不参与任何记录判定                                                                         |
| 重新记录 | 记录结束后的任何一次命中都开启**新连击**，从 1 开始；不沿用旧数字，也不因数字仍在显示而续连                                                                                                                                                                                |
| 回合结束 | `round_end` / `match_end` 后停止记录并清空显示；`round_start` 恢复记录（从空开始）                                                                                                                                                                    |

- **驱动**：`VersusBattle._process` 每帧调用 `ComboTracker.update(delta)`（暂停时冻结）；命中由 `hit_landed` 登记，且仅非格挡才登记。`ComboTracker` 为纯逻辑类，不依赖场景树，便于单独验证。
- **显示与记录严格分离**：`register_hit()` 只看「记录是否进行中 + 是否同一受击方」，从不读取显示计时；`_show_timer` 只用于决定何时返回 `true` 让调用方隐藏标签。因此显示滞留期不是记录窗口，滞留期间的命中会立即刷新数字为 `1 HIT` 并作废旧计时。`last_count` 是连击结束时留存的显示数字，不参与任何判定。
- **抓取**：抓取成立时只进拆投窗口，不发 `hit_landed`；**伤害结算**（`_process_grabbed` → `_on_grabbed_settle`）发出 `combo_hit_landed(attacker, target)`，同样登记一次有效命中。由于 GRABBED / KNOCKDOWN 都在记录范围内，**抓取可以接在连段中间并继续连**（"抓取也能带进连段"）；拆投成功不结算伤害、不发信号，不计入连击。该信号只驱动连击计数，不给抓取额外加火花/定格/音效。
- **格挡**：`hit_landed(blocked=true)` 不是"命中"，不计入连击。
- **与 `Fighter.combo_count` 的区别**：后者是单次招式内的多段命中数（起手/收招清零），仅作角色内部数据，不驱动 HUD 显示。

### 13. 空中可选模块 (空中抓取 / 空中格挡技 / 空中必杀技)

三个模块与空中通常技并列，由角色按需装配，**支持 0 / 1 / N 个**：

| 模块 | 输入 | 数据数组 | 默认下标 |
| ---- | ---- | ---- | ---- |
| 空中抓取 (JD) | 空中 D | `air_grab_attacks` | `air_move_index(GRAB, 0)` |
| 空中格挡技 (JE) | 空中 E | `air_block_attacks` | `air_move_index(BLOCK, 0)` |
| 空中必杀技 | 空中 236/214/623 + A/B/C | `air_special_attacks` | 指令下标 = `SPECIAL_MOTIONS` 顺序，再经 `air_move_index(SPECIAL, i)` |

- **角色差异**：数组为空 = 该角色没有此模块（输入不触发，自然退化）；1 个 = 单招；多个 = 多变体。
- **数据由用户自行管理**：`special_attacks` 与上述三个数组在模板中**全部默认为空**，仓库不预置任何招式。往数组追加 `AttackData` 即刻生效，无需改框架代码。
- **多变体选择钩子**：角色可覆盖 `air_move_index(kind, base_index) -> int`，或直接给 `air_move_selector` 赋值 `Callable(kind, base_index) -> int`（无需为每个角色建子类脚本）。默认返回 `base_index`；返回越界下标视为「本次输入无对应招式」，不触发。框架**不预设方向映射**、不规定变体顺序，选择规则完全由角色脚本决定。钩子应为纯函数（一次输入可能对多条候选指令各调用一次）。
- **触发优先级**（空中）：空中必杀 → 空中抓取 → 空中格挡技 → 空中通常技。指令同时命中多条时取匹配结束最晚者（最新意图），起手成功后 `clear_motion_history` 消耗指令。
- **实现约定**：三个模块统一复用 `ATTACK_SPECIAL` 状态（已在攻击状态分发内，走 `_process_attack`），不新增 / 硬编码格挡或拆投状态；招式性质完全由 `AttackData` 自身字段表达（`attack_type`、`AttackAttribute.GRAB`、`GRAB_BREAK_REQUIRED`、段几何等）。空中起手保留起跳惯性（不清零 `vx`），招式结束按 `_is_grounded()` 回 `IDLE` 或 `JUMP_UP`。
- **与地面的边界**：地面 D / E / 必杀仍走各自原有流程，不读空中数组；取消进必杀仍**仅地面**（空中模块不走取消链）。空中抓取若使用 `AttackAttribute.GRAB`，命中时由 `_on_hit` 转 `_begin_grabbed`，而 `_begin_grabbed` 要求受击方在地面——即「空中抓取打地面对手有效、打空中对手不成立」，这是现有抓取机制的限制，未擅自放开。
- **F 推进**：三个空中模块起手后处于 `_is_in_action()` 状态，方向 + F 推进照常可用。

## 按键映射

| 动作 | P1 | P2 |
| ---- | ---- | ---- |
| 移动 | W / A / S / D | 方向键 |
| A 轻攻击 | J | Numpad 1 |
| B 中攻击 | K | Numpad 2 |
| C 重攻击 | L | Numpad 3 |
| D 抓取 | I | Numpad 4 |
| E 格挡技 | U | Numpad 5 |
| **F 推进** | **O** | **Numpad 6** |
| START 开始/暂停 | Enter | **Numpad 7** |

> **E / F 默认主键已互换**：推进 F = 1P `O` / 2P `Numpad 6`，格挡技 E = 1P `U` / 2P `Numpad 5`。六个动作键各占唯一主键，避免一键触发两个动作；2P START 用 `Numpad 7`，不与 1P 的 `Enter` 或动作键 1~6 冲突。**双方均无副键**（已移除 2P 的主键盘副键）。设置界面可重绑定，自定义值持久化在 `user://input.cfg` 并覆盖默认值；重绑定后该动作同样只保留一枚键。

## 扩展指南

1. **添加新角色**: 复制 `default_fighter.tscn`，替换精灵图，覆盖 `_setup_default_attacks()` 定义专属通常技
2. **添加必杀技**: 往 `special_attacks[0/1/2]`（对应 236/214/623）填入自己的 `AttackData` 即可，空中版填 `air_special_attacks`；指令识别与下标映射框架已就绪，**不需要改** `_handle_attack_input()`
3. **装配空中可选模块**: 往 `air_grab_attacks` / `air_block_attacks` 追加数据即启用 JD / JE，留空则该角色没有此模块（见第 13 节）
4. **多个空中招式**: 覆盖 `air_move_index()` 或给 `air_move_selector` 赋值，按方向 / 按键 / 状态等任意规则返回数组下标
5. **添加新场景**: 参照 `main_menu.tscn` 的结构创建 `.tscn` + `.gd` 组合
6. **调整平衡**: 修改 `global_config.gd` 中的常量即可全局生效
