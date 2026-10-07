// Cache the app shell so it opens offline; refresh the cache in the background.
const CACHE = 'minimal-todo-v2';
const FILES = ['./', 'index.html', 'manifest.webmanifest', 'icon.svg', 'icon-512.png'];
self.addEventListener('install', e => e.waitUntil(caches.open(CACHE).then(c => c.addAll(FILES))));
self.addEventListener('activate', e => e.waitUntil(
  caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
));
self.addEventListener('fetch', e => e.respondWith(
  caches.match(e.request).then(hit => {
    const net = fetch(e.request).then(res => { caches.open(CACHE).then(c => c.put(e.request, res.clone())); return res; });
    return hit || net;
  })
));
