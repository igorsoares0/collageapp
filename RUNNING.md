# Rodando o app — dev e prod

O app escolhe o backend pela variável de build `API_BASE`. Em vez de digitar a
URL toda vez, use os arquivos de ambiente versionados em `env/`:

| Arquivo | `API_BASE` | Para quê |
|---|---|---|
| `env/dev.json` | `http://localhost:3000` | backend local (editor web em `npm run dev`) |
| `env/prod.json` | `https://collageweb-iota-mu.vercel.app` | backend de produção (Vercel + Neon) |

> O app só faz requisições **GET** (templates e assets), e essas rotas são
> públicas. Por isso **nenhum modo precisa de login/credencial** — nem contra o
> deploy de produção, que é protegido por Basic Auth apenas nas páginas do
> editor e nas escritas.

---

## Produção (o normal)

Fala direto com a Vercel pela internet, via HTTPS. **Não precisa** de dev
server, bridge nem `adb reverse` — é só conectar o celular e rodar:

```bash
flutter run --dart-define-from-file=env/prod.json
```

Build de release (APK) apontando pra produção:

```bash
flutter build apk --dart-define-from-file=env/prod.json
```

> A URL fica **congelada** no APK publicado — trocar depois exige recompilar e
> republicar. Se um dia mudar o domínio (limpar o projeto duplicado e assumir
> `collageweb-iota.vercel.app`, ou usar domínio próprio), edite `env/prod.json`
> e gere um novo build.

---

## Desenvolvimento (backend local)

Aponta pro editor web rodando na sua máquina. Passos:

**1. Suba o backend web** (na pasta `collageweb`):

```bash
npm run dev          # Next.js em http://localhost:3000
```

**2. Rode o app em modo dev:**

```bash
flutter run --dart-define-from-file=env/dev.json
```

Como o default do `API_BASE` já é `http://localhost:3000`, um `flutter run`
puro (sem a flag) equivale ao modo dev.

### Fazer o `localhost` chegar no aparelho

`localhost` no celular é o próprio celular — não a sua máquina. Depende de onde
o app roda:

- **Emulador Android:** o host é `10.0.2.2`. Ajuste o `env/dev.json` para
  `http://10.0.2.2:3000` ou passe `--dart-define=API_BASE=http://10.0.2.2:3000`.
- **Device físico via USB (setup WSL deste projeto):** encaminhe a porta com
  `adb reverse`, para o `localhost:3000` do aparelho cair na sua máquina:

  ```bash
  adb reverse tcp:3000 tcp:3000
  ```

  Neste projeto o dev server do Next escuta em IPv6 (`::1`), mas o `adb reverse`
  encaminha para IPv4 (`127.0.0.1`). A ponte `ipv4-bridge.mjs` cobre essa
  diferença (`127.0.0.1:3000` → `::1:3000`) — deixe-a rodando antes do
  `adb reverse`. `EADDRINUSE` ao subir a ponte é benigno: uma instância
  anterior ainda está viva.

---

## Nota WSL

Neste ambiente o `flutter`/`dart` rodam via `cmd.exe`:

```bash
cd /mnt/c/allsaas/collageapp && cmd.exe /c "flutter run --dart-define-from-file=env/prod.json"
```

Depois de mudar o modelo de dados/render, use **hot restart** (`R`) em vez do
hot reload (`r`).
