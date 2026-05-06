# Remodex 上游大版本集成手册

本文档记录本仓库在“本地已深度定制、上游又持续快速演进”的前提下，如何稳定追上最新 upstream，并尽量保留本地能力、降低主分支风险、缩短排障时间。

适用场景：

- 你的仓库已经不是轻量 feature branch，而是长期维护的 fork
- 本地在 `CodexMobile`、`phodex-bridge`、同步链路、文案或产品策略上有大量改动
- upstream 一次更新会带来几十到几百个文件变化
- 直接 `git merge` 会出现大规模 `add/add`、重复定义、状态模型冲突或行为分叉

不适用场景：

- 只有少量本地提交
- 与 upstream 仍然共享稳定历史
- 可以接受直接重置到 upstream 再少量补丁回灌

## 目标

这套流程的目标不是“尽量少改文件”，而是：

1. 保留本地关键定制能力
2. 吃到 upstream 最新可用基线
3. 不污染日常使用的 `main`
4. 最终得到一个能编译、能继续演进、能推送审核的集成分支

## 核心原则

### 1. 不在日常主线硬合

不要直接在本地日常 `main` 上执行大合并。先把 `main` 当成稳定参考，再单独开集成分支和 worktree。

### 2. 把问题当“重新嫁接”，不要当普通冲突解决

当 fork 已经形成产品分叉时，问题本质不是文本冲突，而是：

- 架构边界已经变化
- upstream 新模块和本地旧模块职责重叠
- 状态模型、命名、产品策略已经分叉

此时最有效的方法通常不是逐个冲突块手工点选，而是：

1. 以上游最新版本为新基线
2. 把本地定制按目录或能力整层回灌
3. 用编译和测试把重复模块、接口错位、缺失依赖逐步收平

### 3. 优先保证过程可逆

整个过程应满足：

- 本地 `main` 不动
- 上游基线可随时重建
- 集成 worktree 可随时丢弃重来
- 每一步都能明确知道“这次改的是哪一层能力”

## 推荐分支与目录结构

建议固定使用以下结构：

```text
origin    -> 你的仓库
upstream  -> 原作者仓库

main                              # 你的稳定主线，不直接做大集成
upstream-main                     # 指向 upstream/main 的本地跟踪分支
integration/<topic-or-date>       # 集成分支
/tmp/<repo>-integration           # 独立 worktree
```

示例：

```sh
git remote add upstream https://github.com/Emanuele-web04/remodex.git
git fetch origin --prune
git fetch upstream --prune

git branch -f upstream-main upstream/main
git switch -c integration/upstream-remodex-20260506 upstream/main
git worktree add /tmp/remoteCodex-integration integration/upstream-remodex-20260506
```

## 为什么不用直接 merge

在本仓库这类长期 fork 中，直接 `merge` 常见问题包括：

- 双方默认分支没有可用共同祖先，或共同历史已经失去实际价值
- 大量 `add/add` 冲突
- 同一功能被两边分别实现为不同文件
- 同一文件中，产品策略已经根本分叉
- 文本层面看似能合，运行时却会出现重复定义、状态不一致、行为回退

如果你发现以下信号，基本可以直接放弃“普通 merge”路线：

- 冲突文件超过几十个
- `Services`、`Views/Turn`、桥接层同时爆冲突
- Xcode 工程、包依赖、资源文件也一起冲突
- 一看就是“同名文件已变成不同产品”

## 标准工作流

### 阶段 1：建立安全集成空间

先完成以下动作：

1. 抓取 upstream 最新代码
2. 创建 `upstream-main`
3. 从 `upstream/main` 创建集成分支
4. 创建独立 worktree

这样能确保：

- 你的日常仓库不被污染
- 所有大动作都在 worktree 内完成
- 需要回滚时，直接删除 worktree 即可

### 阶段 2：判断采用哪种迁移策略

常见有三种：

#### 策略 A：逐提交 `cherry-pick`

适合：

- 本地提交数量不多
- 提交边界非常清晰
- 每个提交都相对独立

缺点：

- 在长期 fork 上非常容易失真
- 一个能力通常已经散落到多个提交里
- 解决同一类冲突会反复发生

#### 策略 B：逐文件手工 merge

适合：

- 冲突文件不多
- 文件职责清晰
- 双方差异主要是小修

缺点：

- 文件一多就会变成高噪音机械劳动
- 容易把“文本合对了、行为合错了”

#### 策略 C：以上游为基线，整层回灌本地能力

适合：

- 本地已经深度分叉
- 大部分价值在本地定制，而不是零散提交历史
- 上游更新很大，但你仍想快速追上

这次实践证明，在本仓库当前阶段，策略 C 最稳。

## 本仓库推荐的集成方式

### 第一步：先把 upstream 作为新基线

集成分支从 `upstream/main` 开始，而不是从你的 `main` 开始。

原因：

- 能保证最新上游内容天然齐全
- 能快速判断哪些是“本地缺的”，哪些是“上游新增的”
- 后续的决策会更清晰：是把本地带回来，还是接受 upstream 默认实现

### 第二步：按目录整层回灌本地能力

不要一开始就逐文件修冲突，优先按能力边界或目录边界整体迁回。

本仓库实践中，适合整层回灌的目录包括：

```text
CodexMobile/CodexMobile
CodexMobile/CodexMobileTests
CodexMobile/Vendor
CodexMobile/CodexMobile.xcodeproj
phodex-bridge/src
phodex-bridge/test
relay
skills
Docs
README.md
CONTRIBUTING.md
run-local-remodex.sh
```

这么做的好处：

- 快速恢复本地产品形态
- 先拿回你的主要能力和交互
- 把复杂问题集中到“上游新增模块如何接入”，而不是被海量文本冲突拖住

### 第三步：用编译结果识别真正冲突

整层回灌后，不要猜。直接让工程说话。

建议顺序：

1. `git diff --check`
2. 搜索冲突标记
3. JS 语法检查
4. `xcodebuild`

这一阶段真正要解决的问题，通常不是语法，而是：

- 重复定义
- 同名功能双实现
- 新旧状态模型字段不一致
- 上游新增文件依赖本地不存在的上下文

## 冲突分类方法

下次遇到大更新，优先按下面四类处理，而不是按文件名处理。

### A. 本地产品策略层

例如：

- 文案与术语
- 交互路径
- 设置项表达方式
- 是否保留某个上游商业化或策略入口

处理原则：

- 默认保留本地版本
- 只吸收 upstream 明显新增且不冲突的选项或入口

### B. 本地核心能力层

例如：

- Mac 连接策略
- 自动同步逻辑
- 线程状态恢复
- bridge 的 DNS/代理兼容

处理原则：

- 本地实现优先
- upstream 若有新接口，做最小适配
- 不为了“看起来更像 upstream”而牺牲本地已验证能力

### C. upstream 新增能力层

例如：

- 新的分页模块
- 新的工作区检查点模块
- 新的 companion / pet 功能
- 新的 project picker / 浏览器辅助组件

处理原则：

先问两个问题：

1. 它是全新能力，还是与你本地已有实现重叠？
2. 它依赖的状态模型，与你本地当前架构是否兼容？

如果答案是“高度重叠且不兼容”，优先只保留一套实现。

### D. 资源 / 测试 / Vendor / 文档层

这类通常最适合整批迁移。

处理原则：

- 能整批跟就整批跟
- 如果编译或包管理没出问题，不要过早拆散

## 编译驱动收口法

这是整个流程里最关键的复用经验。

### 1. 先解决重复定义

一旦编译器提示 duplicate symbol、invalid redeclaration、ambiguous use，优先检查：

- 是否同时保留了 upstream 新文件和本地旧文件
- 是否同一能力被拆成两种实现
- 是否新模块引入了你本地已经实现过的类型

这类问题通常不是“补几个字段”能解决，而是应该删掉一边。

### 2. 再解决状态模型不兼容

如果上游新文件依赖本地没有的状态字段、阶段枚举、上下文对象，说明：

- 它不是低成本接入项
- 它与当前本地演进方向不同步

处理方式通常有两种：

- 回退到本地旧实现
- 或暂时移除 upstream 新模块，待后续专门重构再接

### 3. 最后补最小兼容层

只有在某个类型本身仍然合理、只是少量常量或桥接层缺口时，才补最小兼容代码。

不要为了接一个上游文件，把整条本地架构改成 upstream 模型。

## 本次实践中的典型案例

下面这些案例，能帮助下次更快判断。

### 案例 1：设置页策略分叉

表现：

- upstream 与本地对同一设置页的产品策略不同
- 术语已经分叉，例如设备命名和说明方式不同

处理：

- 保留本地交互和文案
- 只吸收不冲突的新配置项

启示：

- 产品策略层不要硬对齐 upstream

### 案例 2：Turn 时间线渲染重复实现

表现：

- upstream 新增渲染投影文件
- 本地原有时间线渲染链路已成立
- 编译时出现重复定义或字段不兼容

处理：

- 删除冲突的 upstream 新文件
- 恢复本地已稳定的时间线视图实现

启示：

- 时间线、状态投影、复杂 reducer 这类模块，一旦两边都进化过，通常只能保留一套主实现

### 案例 3：分页与工作区检查点模块

表现：

- upstream 新增了分页/检查点文件
- 这些文件依赖的上下文与本地当前模型不一致

处理：

- 暂时移除这些 upstream 模块
- 保证主功能先能构建和运行

启示：

- “暂不接入”是合理工程决策，不是失败

### 案例 4：bridge 网络兼容逻辑

表现：

- 本地 bridge 侧有经过实战验证的网络兼容逻辑
- upstream 默认实现未必覆盖你的真实使用场景

处理：

- 本地 bridge 定制优先保留

启示：

- bridge 层是本地 fork 的核心资产，不要轻易被上游覆盖

## 建议保留的固定命令清单

以下命令适合作为每次升级的最小检查集。

### Git 与结构检查

```sh
git remote -v
git branch --show-current
git status --short
git diff --check
git diff --name-status upstream/main...HEAD
```

### 冲突检查

```sh
rg "^(<<<<<<<|=======|>>>>>>>)" .
```

### Node / bridge 检查

```sh
node --check phodex-bridge/src/bridge.js
node --check phodex-bridge/src/codex-desktop-refresher.js
node --check phodex-bridge/src/codex-transport.js
```

### iOS 构建检查

```sh
xcodebuild \
  -project CodexMobile/CodexMobile.xcodeproj \
  -scheme CodexMobile \
  -sdk iphonesimulator \
  -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

如果日志太长，可以只筛关键信息：

```sh
xcodebuild \
  -project CodexMobile/CodexMobile.xcodeproj \
  -scheme CodexMobile \
  -sdk iphonesimulator \
  -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | rg "error:|warning:|BUILD SUCCEEDED|BUILD FAILED"
```

## 什么时候该删 upstream 新文件

满足以下任一情况，可以优先考虑删掉 upstream 新文件，而不是继续硬接：

- 与本地已有能力重复定义
- 依赖大量本地不存在的状态字段
- 接入成本明显大于当前版本收益
- 删掉后主功能能稳定编译且行为没有关键回退

这类删除不是永久否决，而是把问题从“这次大集成”转成“后续专门特性评估”。

## 什么时候该保留 upstream 新文件

满足以下条件时，更适合保留：

- 该能力本地完全没有
- 不会与现有核心架构冲突
- 只需要少量适配即可接入
- 对未来维护成本是净正收益

## 升级完成的验收标准

至少满足以下几点，才能认为这次追 upstream 已经闭环：

1. `main` 未被污染
2. 集成分支已独立存在
3. worktree 内无冲突标记
4. `git diff --check` 通过
5. JS 语法检查通过
6. `xcodebuild` 构建成功
7. 关键本地能力仍然存在
8. 已推送到你的远程仓库，方便继续 PR 或二次整理

## 不建议做的事

- 不要直接在日常 `main` 上试错
- 不要在海量冲突里逐块点选“ours/theirs”赌运气
- 不要为了接一个 upstream 新模块，反向重构整套本地架构
- 不要把“编译过了”误认为“能力没回退”，关键路径仍要人工抽查
- 不要把所有 upstream 新文件都当成必须立即接入

## 后续持续优化建议

如果希望未来每次升级更轻松，建议逐步把本地定制显式分层：

- 连接与同步策略
- bridge / relay / 网络兼容
- UI 文案与产品策略
- timeline / reducer / projection 这类重状态模块
- Vendor 与第三方依赖

分层越清楚，下次越容易做出判断：

- 哪些目录可以整层覆盖
- 哪些模块只能二选一
- 哪些 upstream 新能力值得单独开任务接入

## 一句话方法论

当本地 fork 已经形成自己的产品形态时，追 upstream 的正确姿势不是“解决 merge conflict”，而是“以上游新基线为底，重新嫁接本地能力，并用编译和测试驱动收口”。
