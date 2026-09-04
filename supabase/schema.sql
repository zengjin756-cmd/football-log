-- ============================================================================
-- 绿茵日志 · Supabase 数据库 Schema (schema.sql)
-- 说明:
--   1. 在 Supabase 项目 → SQL Editor → New query 中整体粘贴执行。
--   2. 启用行级安全(RLS), 实现"球员只能改自己、互为好友才可读对方公开资料"。
--   3. 与本地单机原型的数据模型一一对应(见 CLOUD_TABLES / 上云方案评估.md)。
-- ============================================================================

-- 若需重复执行可先删(谨慎): 反向顺序删, 以免外键依赖报错。
-- DROP TABLE IF EXISTS friendships, checkins, summaries, matches, trainings, profiles CASCADE;

-- ============================================================================
-- 1. profiles  球员公开资料(一份一行, 关联 auth.users.id)
-- ============================================================================
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  name        text default '球员',
  pos         text,
  pos_detail  text,
  foot        text,
  height      text,
  weight      text,
  team        text,
  number      text,
  color       text default '#1d8a4e',
  created_at  timestamptz default now()
);

-- ============================================================================
-- 2. trainings 训练记录(owner_id = 谁的记录)
-- ============================================================================
create table if not exists public.trainings (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references auth.users (id) on delete cascade,
  date        date not null,
  type        text,          -- 射门/体能/对抗...
  duration    int,           -- 分钟
  intensity   int,           -- 1-5
  feel        text,
  note        text,
  created_at  timestamptz default now()
);

-- ============================================================================
-- 3. matches 比赛记录
-- ============================================================================
create table if not exists public.matches (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references auth.users (id) on delete cascade,
  date        date not null,
  opp         text,
  home        boolean,
  gf          int default 0,   -- 我方进球
  ga          int default 0,   -- 对方进球
  starts      boolean,
  pos         text,
  goals_n     int default 0,
  assists_n   int default 0,
  yellow      int default 0,
  red         int default 0,
  rating      numeric(3,1),    -- 0-10
  note        text,
  created_at  timestamptz default now()
);

-- ============================================================================
-- 4. summaries 赛后总结(可关联某场比赛, 也可独立)
-- ============================================================================
create table if not exists public.summaries (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references auth.users (id) on delete cascade,
  match_id      uuid references public.matches (id) on delete set null,
  date          date not null,
  content       text,
  highlights    text,
  problems      text,
  improvement   text,
  created_at    timestamptz default now()
);

-- ============================================================================
-- 5. checkins 打卡(每日一条, 唯一约束防止重复)
-- ============================================================================
create table if not exists public.checkins (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references auth.users (id) on delete cascade,
  date        date not null,
  kind        text not null check (kind in ('train','match','rest','inj')),
  created_at  timestamptz default now(),
  unique (owner_id, date)
);

-- ============================================================================
-- 6. friendships 好友关系(对应本地 RELS; 双向一条即可)
--   约定: a < b 字母序存储, 避免重复。
--   status: 'friend' 已互为好友 | 'pending' 待同意
--   note_ab / note_ba: 各自仅自己可见的备注(本地 DB.notes 拆到此)
-- ============================================================================
create table if not exists public.friendships (
  a           uuid not null references auth.users (id) on delete cascade,
  b           uuid not null references auth.users (id) on delete cascade,
  status      text not null default 'pending' check (status in ('pending','friend')),
  at          date,
  last_played date,
  note_ab     text,            -- a 对 b 的备注(仅 a 可见)
  note_ba     text,            -- b 对 a 的备注(仅 b 可见)
  created_at  timestamptz default now(),
  primary key (a, b),
  check (a < b)
);

-- 索引(加速查询)
create index if not exists idx_trainings_owner   on public.trainings (owner_id, date desc);
create index if not exists idx_matches_owner     on public.matches (owner_id, date desc);
create index if not exists idx_summaries_owner   on public.summaries (owner_id, date desc);
create index if not exists idx_checkins_owner    on public.checkins (owner_id, date desc);
create index if not exists idx_friendships_user  on public.friendships (a);
create index if not exists idx_friendships_user2 on public.friendships (b);

-- ============================================================================
-- 7. RLS 行级安全策略
-- ============================================================================
alter table public.profiles      enable row level security;
alter table public.trainings     enable row level security;
alter table public.matches       enable row level security;
alter table public.summaries     enable row level security;
alter table public.checkins      enable row level security;
alter table public.friendships   enable row level security;

-- 辅助函数: 二人是否互为好友
create or replace function public.are_friends(uid_a uuid, uid_b uuid)
returns boolean language sql security definer stable as $$
  select exists (
    select 1 from public.friendships
    where status = 'friend'
      and ((a = least(uid_a, uid_b) and b = greatest(uid_a, uid_b)))
  );
$$;

-- ---- profiles ----
-- 本人可读可改; 好友(单向即可, 互为好友表中含两人)可读; 其余不可见
drop policy if exists "profile_owner_select" on public.profiles;
create policy "profile_owner_select" on public.profiles
  for select using (id = auth.uid() or public.are_friends(auth.uid(), id));
drop policy if exists "profile_owner_insert" on public.profiles;
create policy "profile_owner_insert" on public.profiles
  for insert with check (id = auth.uid());
drop policy if exists "profile_owner_update" on public.profiles;
create policy "profile_owner_update" on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

-- ---- 训练/比赛/总结/打卡: 仅 owner 本人可读写 ----
-- trainings
drop policy if exists "train_owner_all" on public.trainings;
create policy "train_owner_all" on public.trainings
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
-- matches
drop policy if exists "match_owner_all" on public.matches;
create policy "match_owner_all" on public.matches
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
-- summaries
drop policy if exists "summary_owner_all" on public.summaries;
create policy "summary_owner_all" on public.summaries
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
-- checkins
drop policy if exists "checkin_owner_all" on public.checkins;
create policy "checkin_owner_all" on public.checkins
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- ---- friendships ----
-- 仅当事双方可见/可写自己的关系
drop policy if exists "friends_party_select" on public.friendships;
create policy "friends_party_select" on public.friendships
  for select using (auth.uid() = a or auth.uid() = b);
drop policy if exists "friends_party_insert" on public.friendships;
create policy "friends_party_insert" on public.friendships
  for insert with check (auth.uid() = a or auth.uid() = b);
drop policy if exists "friends_party_update" on public.friendships;
create policy "friends_party_update" on public.friendships
  for update using (auth.uid() = a or auth.uid() = b) with check (auth.uid() = a or auth.uid() = b);

-- ============================================================================
-- 8. 自动: 新用户注册时建 profile + 预设默认资料
-- ============================================================================
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', '球员'));
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
