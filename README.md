# 五筆字型

配方： ℞ **wubi**

这是一个基于 [Rime](https://rime.im) 引擎深度定制的五笔字型输入方案。在标准 86 版五笔之上，结合了强力的 Lua 扩展脚本（`rime.lua`，14 个模块），实现了极速在线造词、动态词频与多维度智能候选过滤，为您提供干净、极致的输入体验。

> 本方案包含两套输入方案：**wubi**（五笔主方案）与 **pinyin_simp**（拼音辅助方案，用于反查与临时输入），共享同一套 Lua 扩展、英文词库与快捷键风格。另附 **English** 独立英文方案。

## 核心功能

* **86 五笔基础**：以 86 五笔编码为基础（beavailable 编码修改版），个别码位优化；集成 8105 单字表与两级词库，支持简码、词组输入。
* **简繁切换**：一键切换简体与香港繁体（`Control + Shift + 4`）。
* **拼音反查**：输入 `/` + 拼音可反查五笔编码，辅助学习或临时输入生僻字。
* **英文混输优化**：内置英文词库（11000+ 词条：5000+ 常用词及绝大多数计算机术语、英文简写）。支持根据输入自动调整英文大小写（`autocap_filter`），连续上屏英文单词时自动追加空格（`en_spacer`）。
* **日期时间快捷输入**：`rq`（日期：2026-07-28 / 2026年7月28日）、`sj`（时间：14:30）、`xq`（星期）、`dt`（完整时间）、`ts`（时间戳）。
* **财务数字快捷输入**：支持 `Shift + 字母` 或大写字母开头混合数字（如 `A123.4` ➔ `壹佰贰拾叁元肆角整`），同时支持小写人民币数字；内置防越界保护及原版"0转1"逻辑修正。识别模式兼容 U/V 缺省（`^[A-TV-Z]+[0-9]+$`）。
* **Emoji 支持**：可输入常用 Emoji 表情，配合降频过滤器自动后置，不干扰中文输入。
* **万象语法模型**：内置 `wanxiang-lts-zh-hans.gram`（拼音方案启用），提升长句转换准确度。

## 特色功能（Lua 驱动）

| 模块 | 功能 |
|---|---|
| `submit` | **沉浸式无干扰造词**：上屏文本后按 `Ctrl + Enter` 唤出交互界面，赋予编码回车即永久写入 `dicts/wubi.chaos.dict.yaml` 并同步内存，无需重启。支持左右方向键调整历史词范围；编码输入阶段自动拦截引擎默认杂乱候选 |
| `paging_or_commit` | **智能单页顶字上屏**：候选仅有唯一一页时，按 `,`/`.` 直接将当前焦点词上屏并自动补全中文标点 `,`→`，`、`.`→`。`；多页时则正常翻页 |
| `sort_filter` | **长词后置与智能排序**：4 码及以上时词组优先、单字/英文后置（词组不足 3 个时自动解除压制）；短码（<4 码）透传不干预 |
| `reduce_english_filter` | **词汇智能降频**：约 180 个易误触英文单词（and/the 类高频小词）自动后置 |
| `reduce_emoji_filter` | **Emoji 降频**：特定 Emoji 自动后置 |
| `repeat_last_input` | **Z 键重复上屏**：`z` 直接重复上一次上屏内容（权重 5，置顶命中）|
| `pin_cand_filter` | **简码保护与强行置顶**：预设「一简 → 高频词列表」映射（如 `q → 去/其实/岂不是`），固定候选不被造词或长词覆盖 |
| `manual_segmentation` | **手动分词**：用反引号 <code>`</code> 分隔编码段，隔离造句引擎，精确控制组词边界 |
| `select_character` | **以词定字**：`[` 提取候选词首字上屏，`]` 提取尾字上屏；同时记录字频到 `dicts/wubi.freq.txt` |
| `weight_updater` | **权重离线结算**：基于使用日志自动计算词频增益（简码加成/码长衰减/虚词惩罚），阅后即焚 + 日志按日期轮转 |

## 操作与快捷键

### 候选与翻页

| 按键 | 行为 |
|---|---|
| `;` / `'` | 选第二 / 第三候选 |
| `,` / `.` | 多页时向前 / 向后翻页；唯一一页时直接顶字上屏＋中文标点 |
| `Tab` / `Shift+Tab` | 向下 / 向上翻页 |
| `[` / `]` | 以词定字：提取候选首字 / 尾字上屏 |
| `Enter` | 输出原生字母/换行（绑定 Shift+Enter 行为）|

### 开关切换

| 快捷键 | 功能 |
|---|---|
| `Control + ;` 或 `Control + Shift + 3` | 中英标点切换 |
| `Control + Shift + 4` | 简 ↔ 繁（香港）切换 |
| `Control + Shift + 5` | 连续模式（continuous_mode）开关 |
| `Control + Shift + L` | 三连确认学习（triple_confirm_learn）开关 |
| `Control + 0` | 输入法设置菜单（方案切换器）|
| `Ctrl + Enter` | 手动造词 |

### 特殊触发

| 输入 | 结果 |
|---|---|
| `/pinyin` | 拼音反查五笔编码 |
| `z` | 重复上次上屏内容 |
| `z` 混入编码（如 `a?c`）| 万能 Z 键正则模糊匹配未知编码 |
| `rq` / `sj` / `xq` / `dt` / `ts` | 日期 / 时间 / 星期 / 完整时间 / 时间戳 |
| 大写字母+数字（如 `A123.4`）| 中文大写金额 |

## 词库结构

```
wubi.dict.yaml                 # 主码表入口（sort: by_weight）
├─ import:
│   ├─ dicts/wubi.word         # 8105 单字库（10,487 行）
│   ├─ dicts/wubi.phrase       # 固定词库（17,564 行）
│   ├─ dicts/wubi.user         # 自用词、不规定造词（322 行）
│   ├─ dicts/wubi.long         # 超过 4 码的长词组（286 行）
│   └─ dicts/wubi.chaos        # 手动造词落盘文件（Lua 实时追加，自动压缩清理）
└─ columns: text / code / weight / stem

English.dict.yaml              # 英文词库（11,138 行，含 wubi.low 低频词库）
pinyin_simp.dict.yaml          # 拼音反查词库（导入 dicts/py，205 万行）
dicts/wubi.freq.txt            # 字频记录（Lua 自动写入，weight_updater 消费）
dicts/wubi.xuci.dict.yaml      # 虚词列表（权重更新时 ×0.6 惩罚）
```

## 配套配置文件

| 文件 | 用途 |
|---|---|
| `default.custom.yaml` | 方案清单（wubi + pinyin_simp）、切换器热键、菜单样式、Lua 加载 |
| `weasel.custom.yaml` | 小狼毫外观：roseo_maple 配色（深浅双版）、字体（Microsoft YaHei + Emoji 字体栈）、内嵌编码模式 |
| `installation.yaml` | 安装信息（Weasel 0.17.4 / rime 1.13.1）|
| `user.yaml` | 用户状态记忆（上次方案、开关状态）|

## 手动加词及词频调整

* **在线极速造词**：输入需要组合的文本并上屏后，按 `Ctrl + Enter` 唤出交互界面，赋予编码后按回车，写入 `dicts/wubi.chaos.dict.yaml`，无需重启输入法即可永久生效并置顶（权重 9999）。
* **动态词频自学习**：正常使用中，`select_character` 自动记录字频到 `wubi.freq.txt`；累计 200 次提交后 `weight_updater` 触发一次离线结算，把增益写回各分词库（828↑/0↓ 级别的批量更新，详见 `dicts/wubi.weight.update.log`）。
* **虚词惩罚**：编辑 `dicts/wubi.xuci.dict.yaml` 列出的虚词在权重结算时自动乘 0.6，防止「的了是」等虚词抢占候选位。

## 适用场景

* 习惯使用 **86 五笔**、希望输入法**简洁高效且无卡顿**、需要**沉浸式快捷造词**、**中英混输无缝切换**、**单页智能上屏**、**金额/日期快捷输入**等硬核进阶功能的开发者或文字工作者。
* 如果需要进一步自定义：
  * 编辑 `custom_phrase.txt` 式的自定义短语（对应本方案的 `dicts/wubi.user.dict.yaml`）；
  * 直接调整 `wubi.schema.yaml` 中的参数开关（switches、key_binder、translator 权重等）；
  * 调整 `rime.lua` 各模块顶部常量（如 `COMMIT_THRESHOLD = 200` 结算阈值）。

# 86版五笔字根改版表
![](https://github.com/ernsky/tuku/blob/01407ccfa2add1b3782bd338bc339b9aa2748e47/image/WallPaper-005-3120x2080.png)
