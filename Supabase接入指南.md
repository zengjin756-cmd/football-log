# 绿茵日志 · Supabase 接入指南

> 配套文件：`supabase/schema.sql`（建表+RLS）｜数据层"云接入准备层"已内嵌于 `index.html`。
> 前置：已在 Supabase 完成项目创建。

---

## 0. 这篇文档帮你做什么

一步步把当前"单机本地版"接上 Supabase，让：
- 账号变真实注册（不再用演示账号模拟）
- 数据存云端、跨设备同步
- 好友看到的是真数据（RLS 保证权限）

> 接云是一个渐进过程。**先跑通"最小闭环"，再扩展**，不要一次全改。

---

## 1. 前置准备（一次性）

### 1.1 注册 Supabase 并建项目
1. 打开 https://supabase.com → 用邮箱注册（免费）
2. Dashboard → **New project**
   - 取个名字（如 `football-log`）
   - 设置数据库密码（务必记住，用于后台）
   - 选区域（如 `Southeast Asia (Singapore)`，国内访问相对快）
3. 等约 1–2 分钟项目创建完成

### 1.2 拿到两个关键值
项目创建后进入项目首页 **Project Settings → API**：
- **Project URL**：形如 `https://xxxx.supabase.co`
- **anon public key**：形如 `eyJhbGciOi...`（以 `eyJ` 开头的一长串）

> anon key 是公开的、可放前端；真正保密的 service_role key 绝不能放前端。

---

## 2. 建表（粘贴执行 schema.sql）

1. Supabase 左侧菜单 → **SQL Editor**
2. 点 **New query**
3. 粘贴 `supabase/schema.sql` 全部内容
4. 点 **Run**
5. 看到多条 `Success` 即建表成功

> 脚本会建 6 张表（profiles/trainings/matches/summaries/checkins/friendships）+ 全部 RLS 策略 + 新用户自动建档触发器。可在 **Table Editor** 里查看确认。

---

## 3. 前端接入（改动集中在 index.html 数据层）

### 3.1 引入 supabase-js SDK
在 `index.html` 的 `<head>` 里加一行（CDN 版）：

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
```

### 3.2 填入 key 并开启云
在 index.html 数据层"云接入准备层"处修改：

```js
const CLOUD_ENABLED = true;                    // ← 改为 true
const CLOUD_CONFIG = {
  supabaseUrl: 'https://你的项目.supabase.co',  // ← 填入 Project URL
  supabaseAnonKey: 'eyJhbGciOi...',            // ← 填入 anon public key
  projectRef: null,
};
```

### 3.3 把数据读写切到云端（核心改造点）

本地版数据全走这 4 个函数，接云时把它们改成"云端优先"：

| 本地函数 | 云端对应（Supabase） | 说明 |
|---------|--------------------|------|
| `readBox(u)` | `select * from <table> where owner_id = u` | 从本地同步读 → 云端 async 读 |
| `writeBox(u,d)` | `upsert` 各表 | 本地整包写 → 云端按表写 |
| `persistRels()` | `friendships` upsert | 关系表上云 |
| `loginAs(u)` | `auth.signInWithPassword()` / `getUser()` | 模拟切换 → 真实登录 |

> ⚠️ **关键点**：本地是"同步 + 整包读写 + DB 全局对象"，云端是"异步 + 按表读写"。接云时读取会从同步变异步，需把读取入口（`viewFriend`/`renderStats` 等里直接 `readBox(u)` 的地方）改成 `await`。这正是"云接入准备层"注释里提示的接入原则——**改 4 个入口函数，业务调用方尽量少动**。

### 3.4 登录界面
- 现有 `switchAccount()`（演示账号切换）可保留用于开发，但真用户走注册/登录
- 注册：`CLOUD.register(email, pass)` → 触发 `handle_new_user` 自动建 profile
- 登录：`CLOUD.login(email, pass)`

---

## 4. 最小闭环验证清单

按顺序走通即表示接云成功：

- [ ] 1. 打开页面，控制台 `CLOUD.status()` 显示 `{enabled:true, sdk:true}`
- [ ] 2. 用邮箱注册一个账号 → 自动生成空 profile
- [ ] 3. 登录 → 录一场比赛 → **Table Editor** 的 `matches` 里出现该行，owner_id = 你的 uid
- [ ] 4. 注册第二个账号，两者互加好友 → `friendships` 出现 `status='pending'` → 对方同意变 `friend`
- [ ] 5. 互为好友后，B 能看到 A 的 profile；**未加好友的 C 看不到**（RLS 生效）
- [ ] 6. 换设备/清缓存再登录 → 数据还在（云端持久化）
- [ ] 7. 在 SQL Editor 试一句：用 C 账号查 A 的 matches → 应返回空（权限正确）

---

## 5. 演示数据（可选）

原型的演示账号数据目前存本地。上云后如需"示例数据"：
- 可写一个临时脚本，把 `demoDataOf(u)` 的 JSON 转成各表 insert 语句灌入，owner_id 指向测试账号
- 或保留本地版做展示，云端只跑真实用户数据

---

## 6. 常见问题

**Q：接云后原来的本地数据会丢吗？**
不会。本地数据仍在浏览器，云端是新增的一套。建议接云时先导出本地 CSV/JSON 留底，如需迁移再用脚本导入。

**Q：anon key 放前端安全吗？**
安全。anon key 默认只允许走 RLS 策略能访问的数据；真正的危险操作被 RLS 挡住了。别暴露 service_role key 即可。

**Q：免费额度够吗？**
早期足够：500MB 库、5 万月活认证。免费项目若 7 天无数据库活动会休眠（约 30 秒唤醒），可定时 ping 一张表保活，或用 `CLOUD.connect()` 常开触发。

**Q：页面访问还走 GitHub Pages 吗？**
走。前端仍是静态托管，只是数据读写指向云端。GitHub Pages + Supabase 是常见的免费前后端组合。

---

## 7. 分阶段建议回顾

| 阶段 | 做什么 | 是否需你操作 |
|------|--------|-------------|
| P0 ✅ | 云接入准备层已内嵌 index.html（默认关闭、不影响现有） | 无需 |
| P1 ✅ | `schema.sql` 建表+RLS 已备好 | 建项目后粘贴执行 |
| P2 | 最小闭环（改数据层入口函数为异步接云端） | 需提供 URL+key，我协助改代码 |
| P3 | 跨端完善、真统计 | 协作 |
| P4 | 上线监控备份 | 视情况 |

---

*接入过程中如卡住，随时把报错贴给我，我来排错。*
