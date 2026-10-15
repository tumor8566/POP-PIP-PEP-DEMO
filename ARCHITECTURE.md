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
│   │   ├── input_handler.gd   # 输入处理: 双人输入+缓冲+方向检测
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
│   │   ├── versus_battle.gd   # 对战场景主控制器
│   │   └── training_dummy.gd  # 训练假人AI
│   └── hud/
│       └── battle_hud.gd      # 对战HUD: 血量/气槽/计时器/连击
│
└── resources/                 # 资源文件
    ├── characters/
    │   └── default_fighter.tscn  # 默认角色模板
    └── stages/                   # 场地资源(待添加)
```

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

每招攻击有完整的帧数据:

- `startup_frames` → `active_frames` → `recovery_frames`
- 支持取消链: 轻→中→重→必杀技
- 上/中/下段判定 + 削血 + 浮空追击

### 3. 输入系统 (InputHandler)

- 双人独立输入: P1用WASD+JKLIO, P2用方向键+Numpad
- 8帧按钮输入缓冲(取消窗口)
- 24帧指令识别方向历史(与按钮缓冲分离, 详见第11节)

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

- 空中**仅 A/B/C（轻/中/重）有效**，D（抓取）/E（格挡）及必杀指令在空中被忽略（`_handle_attack_input(airborne := true)` 分支）。
- 招式数据默认由地面同键位攻击**深拷贝微调**生成（`air_*_attacks` 数组，角色差异化数据到位后直接覆盖即可）：
  - 出招帧 +1（`AIR_ATTACK_TRIGGER_DELAY`），判定框纵向 ×0.8（`AIR_ATTACK_SIZE_MULT`）；
  - 伤害/击退/硬直等沿用地面版，起跳惯性保留（空中攻击不清零速度）。
- 深拷贝必须显式处理段数组：`Segment` 是 RefCounted，`Resource.duplicate(true)` **不会**带上 `segments`，且共享段对象会让空中微调污染地面版数据；故用 `AttackData.Segment.duplicate_segment()` 逐段拷贝后整体赋值（见 `attack_data.gd` 与 `fighter.gd` 的空中攻击构建段）。

### 9. 冲刺 (Dash) 双击识别

- 双击识别（`_check_dash_input`）**先于行走判定**执行（`_handle_universal_input` 内顺序保证），避免单击后误入行走导致双击丢识别。
- `buffer_timer` 每次按方向置 `DASH_BUFFER_FRAMES`（15 帧）并逐帧递减：窗口内第二次同方向 = 冲刺；窗口过期后重新单击 = 正常行走（冒烟测试覆盖：单击行走/缓冲过期不冲/双击前后冲刺）。

### 10. 判定框生命周期注意事项 (Hitbox)

- `Hitbox.deactivate()` 失效时会把碰撞形状挪到远处（`shape_node.position = (100000, 0)`），而非仅置 `monitoring = false`：Area2D 监视是单向持续注册的，形状留在原处会让对方受击框保持"已进入"而不产生退出事件，导致下次激活恢复几何时**不再触发 `area_entered`，命中被静默漏掉**（第二段及以后全部丢判定）。
- 不要用 `CollisionShape2D.disabled` 切换（运行时重新启用不会与已有监视者重配）或 `monitorable` 切换（物理服务器重配监视对有延迟，进入信号会晚于判定框失效到达，同样漏命中）。
- 角色 `.tscn` 中的判定框/受击框形状子资源必须 `resource_local_to_scene = true`：否则多实例共享同一 `RectangleShape2D`，`_apply_segment()` 改写 `extents` 会互相污染。

### 11. 必杀技指令 (QCF 236 / QCB 214 / DP 623)

指令识别基于**朝向相对**数字方向（6=朝对手；角色朝左时屏幕方向自动水平翻转，`_flip_numpad_horizontal`），在 `InputHandler` 的 24 帧指令历史（`MOTION_HISTORY_FRAMES`，与 8 帧按钮取消缓冲分离）中做**子序列匹配**；同时命中多个指令时取匹配结束最晚者（输入意图最新）。

| 指令 | 输入 | 默认招式(`special_attacks` 下标) | 备注 |
| ---- | ---- | ---- | ---- |
| QCF 236 | 下(2)→下前(3)→前(6) | [0] 气拳 | 原有 |
| QCB 214 | 下(2)→下后(1)→后(4) | [1] 崩拳 | 高击退 |
| DP 623 | 前(6)→下(2)→下前(3) | [2] 升龙拳 | 对空升龙, `causes_knockdown` 击飞倒地 |

- **触发键**：指令 + A/B/C 任一攻击键（招式由指令区分，不由按键区分）；指令不成立退化为通常技；乱序/滑出窗口(>24帧)不识别。
- **起手与取消**均可触发（取消过第一段触发帧后，`_check_cancel_input`）；成功后 `clear_motion_history` **消耗**指令历史，防止同一次输入重复触发。
- 默认招式数据在 `Fighter._setup_default_attacks()` 构建，角色差异化数据到位后直接覆盖 `special_attacks` 数组即可（必杀技数据由用户自行管理）。
- 升龙拳命中站地上的对手走 `KNOCKDOWN → LIEDOWN → 受身/起身` 全链：`_process_knockdown` 有 2 帧保护且上升中(`velocity.y < 0`)不判落地——否则起跳当帧 `is_on_floor()` 的旧值 `true` 会把击飞升空误判为已落地，直接跳进躺地。

## 按键映射

| 动作   | P1      | P2           |
| ---- | ------- | ------------ |
| 移动   | W/A/S/D | 方向键          |
| 轻攻击A | J       | Numpad 1     |
| 中攻击B | K       | Numpad 2     |
| 重攻击C | L       | Numpad 3     |
| 抓取 D  | U       | Numpad 4     |
| 格挡E  | I       | Numpad 5     |
| 开始   | Enter   | Numpad Enter |

## 扩展指南

1. **添加新角色**: 复制 `default_fighter.tscn`，替换精灵图，覆盖 `_setup_default_attacks()` 方法定义专属招式
2. **添加必杀技**: 在 `Fighter.gd` 的 `_handle_attack_input()` 中添加指令检测和特殊攻击
3. **添加新场景**: 参照 `main_menu.tscn` 的结构创建 `.tscn` + `.gd` 组合
4. **调整平衡**: 修改 `global_config.gd` 中的常量即可全局生效
