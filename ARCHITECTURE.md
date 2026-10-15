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
│   │   ├── fighter_state.gd   # 状态枚举: 25种格斗状态
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

角色共有 **22种状态**，按类别分为:

- **移动类**: IDLE / WALK_FORWARD / WALK_BACK / DASH_FORWARD / DASH_BACK / CROUCH
- **跳跃类**: JUMP_UP / JUMP_FORWARD / JUMP_BACK
- **防御类**: STAND_BLOCK / CROUCH_BLOCK
- **攻击类**: ATTACK_LIGHT / ATTACK_MEDIUM / ATTACK_HEAVY / ATTACK_SPECIAL / GRAB
- **受击类**: HIT_STUN / GRABBED / KNOCKDOWN / SOFT_KNOCKDOWN / WAKEUP
- **系统类**: ESCAPE (脱离) / CRASHED (相杀)
- **演出类**: INTRO / VICTORY / DEFEATED

### 2. 攻击系统 (AttackData)

每招攻击有完整的帧数据:

- `startup_frames` → `active_frames` → `recovery_frames`
- 支持取消链: 轻→中→重→必杀技
- 上/中/下段判定 + 削血 + 浮空追击

### 3. 输入系统 (InputHandler)

- 双人独立输入: P1用WASD+JKLIO, P2用方向键+Numpad
- 8帧输入缓冲
- 输入历史记录(为必杀技指令识别做准备)

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
