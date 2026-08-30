// Cache só do app shell estático (CSS/JS/ícones/manifest). Páginas LiveView
// não são interceptadas aqui: elas dependem do socket para funcionar, então
// servir uma versão em cache delas offline seria só uma tela morta.
const CACHE_NAME = "quiz-shell-v1"

const SHELL_ASSETS = [
  "/assets/css/app.css",
  "/assets/js/app.js",
  "/manifest.json",
  "/favicon.png",
  "/images/icon-192.png",
  "/images/icon-512.png",
]

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_ASSETS))
  )
  self.skipWaiting()
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((names) =>
      Promise.all(
        names
          .filter((name) => name !== CACHE_NAME)
          .map((name) => caches.delete(name))
      )
    )
  )
  self.clients.claim()
})

function isShellAsset(url) {
  return (
    url.origin === self.location.origin &&
    (url.pathname.startsWith("/assets/") || url.pathname.startsWith("/images/"))
  )
}

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url)

  if (event.request.method !== "GET" || !isShellAsset(url)) return

  event.respondWith(
    caches.match(event.request).then((cached) => {
      if (cached) return cached

      return fetch(event.request).then((response) => {
        if (response.ok) {
          const clone = response.clone()
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone))
        }
        return response
      })
    })
  )
})
