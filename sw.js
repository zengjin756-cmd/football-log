/* 绿茵日志 - Service Worker（PWA 离线/加速用） */
const CACHE = 'football-log-v1';
const CORE = [
  './',
  './index.html',
  './manifest.json',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon-maskable-192.png',
  './icons/icon-maskable-512.png'
];
const CDN_ALLOW = ['cdn.jsdelivr.net'];  // 允许缓存 supabase-js 等外网资源

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(CORE)).then(()=>self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k))))
      .then(()=>self.clients.claim())
  );
});

// 网络优先 - 回退缓存（保证云端登录/数据用最新资源）
self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  // Supabase API 永不使用缓存
  if (url.hostname.endsWith('supabase.co')) return;

  // CDN 资源: stale-while-revalidate
  if (CDN_ALLOW.includes(url.hostname)) {
    e.respondWith(
      caches.open(CACHE).then(c => c.match(req).then(cached => {
        const fetchP = fetch(req).then(r => { if(r.ok) c.put(req,r.clone()); return r; }).catch(()=>cached);
        return cached || fetchP;
      }))
    );
    return;
  }

  // 同源资源: 网络优先, 失败用缓存
  e.respondWith(
    fetch(req).then(r => {
      if(r.ok && (req.url.startsWith(self.location.origin))) {
        const copy = r.clone();
        caches.open(CACHE).then(c => c.put(req, copy));
      }
      return r;
    }).catch(() => caches.match(req))
  );
});
