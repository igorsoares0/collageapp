# Checklist de lançamento — Google Play (teste fechado)

Estado em **2026-08-07**, no commit `104e8a7`.

Escopo: **só Android**. iOS está fora — o projeto nunca foi buildado pra iOS e
o desenvolvimento acontece em Windows/WSL, onde nada de iOS é verificável.

## TL;DR

**Não há mais nenhum bloqueio técnico — nem de código, nem de site.**
Reverificado em 2026-08-07: `flutter analyze` limpo ("No issues found"),
**253 testes passando**, nenhuma mudança real pendente (o `git status` gigante
é só CRLF vs LF — `git diff --ignore-all-space` sobre `lib/`, `android/` e
`env/` volta vazio). Assinatura de release, `targetSdk 36`/`minSdk 24` (defaults do Flutter
3.44.7, via `flutter.targetSdkVersion`) e monetização estão todos de pé.

Os dois bloqueios que este documento carregava **caíram**:

- **`/privacy` e `/terms` respondem 200** e servem as páginas de verdade
  ("Privacy Policy · Layer" / "Terms of Service · Layer"), fora do Basic Auth.
- **Domínio próprio no ar**: `env/prod.json` aponta pra `uselayer.online` e
  `api.uselayer.online` (commit `02a80cd`), não mais pro host auto-gerado da
  Vercel.

`/api/templates` e `/api/assets` também respondem 200.

Sobra **uma linha de código**: `pubspec.yaml` continua em `version: 1.0.0+1`, o
mesmo versionCode que já está na internal test. Como o versionCode é único no
app inteiro, o upload pro teste fechado precisa de **`1.0.0+2`** (ver "🚀 Gerar
e subir o AAB"). Fora isso, é formulário de Play Console e arte de ficha.

> **Build de release reverificado em 2026-08-07** (`flutter build appbundle
> --dart-define-from-file=env/prod.json`): sucesso em 303s, 56,2 MB, sem o
> warning de debug key. Conferido dentro do `.aab`:
> - assinado com o upload keystore — `CN=Collage Studio`, SHA-256 batendo com o
>   registrado abaixo, validade até 2053;
> - chave `goog_` de produção e `api.uselayer.online` presentes em
>   `libapp.so` nas 3 ABIs; a chave `test_` e o fallback `localhost:3000`
>   **ausentes**;
> - libs nativas alinhadas em `0x10000` (64 KB), o que satisfaz a exigência de
>   **16 KB page size** que o Play cobra de quem tem targetSdk 35+.
>
> Esse AAB é buildável e assinável hoje — o que falta nele é só o versionCode.

O relógio dos **12 testers / 14 dias** só começa a contar quando o primeiro AAB
estiver numa trilha de **teste fechado** — a internal test onde ele está hoje
**não conta** (ver "📋 Play Console"). Calendário é o recurso escasso aqui,
código não. Por isso a regra de bolso deste documento: **o que não impede o AAB
de subir, sobe depois, durante a janela.**

---

## ✅ Monetização — funcionando ponta a ponta

> O título desta seção era "o app abre, mas ninguém consegue pagar". Isso deixou
> de ser verdade em 2026-07-28, quando a compra de teste passou no device. O
> histórico abaixo fica registrado porque as armadilhas se repetem em qualquer
> re-setup.

### Chave do RevenueCat

O SDK nativo do RevenueCat **rejeita uma chave de Test Store em build não-debug**
e a rejeição não passa pelo `try/catch` do Dart — o app morria antes de pintar a
primeira tela. Não é um bug a corrigir: é a proteção do RevenueCat contra
publicar com chave de teste.

**Resolvido:** a chave virou `REVENUECAT_KEY`, variável de build lida de
`env/*.json` (`lib/src/api/entitlements.dart`), e `env/prod.json` hoje carrega a
chave `goog_` de produção. A monetização funciona ponta a ponta.

> ✅ **A armadilha foi desarmada (2026-07-31).** O `defaultValue` da constante em
> `entitlements.dart` era a chave `test_`, pra que um `flutter run` sem flag
> rodasse em modo dev. A consequência era que **um `flutter build appbundle`
> sem `--dart-define-from-file=env/prod.json` gerava um AAB que subia
> normalmente no Play e crashava em 100% dos aparelhos**, antes da primeira
> tela.
>
> O default agora é **vazio**: uma flag esquecida produz um app que roda com
> monetização desligada, não um app que morre na abertura. A chave `test_`
> continua existindo, só que apenas dentro do `env/dev.json` — mexer no paywall
> em dev exige `--dart-define-from-file=env/dev.json`. Continua valendo passar a
> flag sempre; o que mudou é o custo de esquecer. Ver "🚀 Gerar e subir o AAB".

### Onde parou em 2026-07-28

Feito:

- [x] Chave `goog_` no `env/prod.json`, e verificada dentro do AAB
- [x] App criado no Play Console + **AAB na internal test**
- [x] Assinatura `collage_pro` com base plans `monthly` e `annual`, ambos **ativos**
- [x] Service account `revenuecat@mobileapps-503818.iam.gserviceaccount.com`,
      criada do zero no projeto Google Cloud `mobileapps`
- [x] 3 APIs habilitadas: Google Play Android Developer, Google Play Developer
      Reporting, Google Cloud Pub/Sub
- [x] 2 papéis IAM: **Editor pub/sub** (`pubsub.editor`) e **Visualizador de
      monitoramento** (`monitoring.viewer`)
- [x] Service account convidada no Play Console com os três acessos
- [x] JSON gerado e salvo no RevenueCat

- [x] Credenciais **validadas** no RevenueCat

> **A armadilha que custou a tarde:** o RevenueCat acusava *"Credentials need
> attention"* com a mensagem *"Google Play package name was not found"*, o que
> parecia erro de package name ou propagação de 36h. Era nenhum dos dois — o
> release da internal test estava em **rascunho**. Subir o AAB não publica: o
> release precisa de *Revisar versão → Iniciar lançamento*. Enquanto não
> publica, a API de compras do Google não resolve o package.
>
> O **View details** do aviso é o que dá o diagnóstico: ele quebra a validação
> em três checagens separadas. Ler catálogo e base plans passava; só a de
> *subscription purchases* falhava — o que isola o problema no app não estar
> publicado, e não nas credenciais.

- [x] Notificações em tempo real (Pub/Sub) conectadas nos dois sentidos
- [x] Products, Entitlement `pro` e Offering `default` configurados
- [x] **Paywall listando os dois planos no device**

> **Segunda armadilha da tarde — offering herdada da Test Store.** O projeto no
> RevenueCat existia desde 14/07 com uma offering `default` já marcada como
> *current* e com os packages `$rc_monthly`/`$rc_annual` corretos — mas os
> produtos dentro deles eram os da **Test Store** (`pro_monthly`, `pro_annual`).
> Ao adicionar o app Google Play, a linha dele em cada package fica em **"No
> product"**, e o dashboard não sinaliza isso em lugar nenhum: Products aparece
> "Published", Entitlements aparece "1 Entitlement", a offering aparece
> "2 packages". Só abrindo o package em modo de edição é que o buraco aparece.
>
> No device o efeito é a offering chegar vazia e o paywall cair em *"Plans are
> unavailable right now"* — a mesma tela que aparece quando não há rede.
>
> **Onde olhar:** *Offerings → default → Packages → Edit* → a linha do app
> Android de cada package. Um package carrega um produto por loja; manter o da
> Test Store ao lado do Play é o correto, o SDK escolhe conforme onde roda.

- [x] **Compra de teste concluída com sucesso no device** — monetização
      funcionando ponta a ponta

**A configuração está encerrada.** Não há mais nada a configurar em RevenueCat,
Google Cloud ou na parte de monetização do Play Console.

### Tratamento de erro do fluxo de compra (2026-07-31)

O caminho feliz já estava validado no device; o que faltava era o caminho
infeliz, que é a maioria das interações reais com um paywall. Feito:

- [x] **Cancelamento deixou de ser erro.** Todo `PlatformException` colapsava em
      "Purchase not completed.", então quem só fechava a sheet do Google levava
      uma mensagem de erro. Agora `PurchasesErrorHelper.getErrorCode` separa os
      casos (é o snippet oficial da doc de *Making Purchases*) e cancelamento
      **não diz nada**.
- [x] **Pagamento pendente** (`paymentPendingError` — dinheiro, transferência,
      aprovação dos pais) tem mensagem própria: o pro destrava sozinho pelo
      listener, e o usuário precisa saber que não deve comprar de novo.
- [x] **`productAlreadyPurchasedError`** manda restaurar em vez de recomprar;
      **`networkError`/`offlineConnectionError`** falam em conexão.
- [x] **Race de cold start.** `main()` dispara `init()` sem await, e o paywall
      pedia offerings no `initState` — quem chegasse rápido batia antes do
      `configure()` e via *"Plans are unavailable right now"* com a conta
      perfeitamente saudável, indistinguível da offering vazia acima. Agora
      todo acesso ao SDK espera o future do `init()`.
- [x] **Restore sem compras** dizia "Purchase not completed." no paywall (o
      Settings já acertava). Os dois usam a mesma tabela de mensagens agora.
- [x] **"Manage subscription"** no Settings pra quem é Pro, via
      `CustomerInfo.managementURL`. O Play espera caminho de cancelamento
      dentro do app.
- [x] `buy()` usa o `CustomerInfo` que o próprio `purchase()` devolve — um
      round-trip a menos e sem janela de cache desatualizado.
- [x] O listener passou a ser registrado **antes** do primeiro fetch, então um
      primeiro run offline se corrige sozinho em vez de ficar free até o app
      ser morto.

Cobertura: 3 testes novos em `test/paywall_gate_test.dart` (cancelamento,
pending, restore vazio). **253 testes passando**, `flutter analyze` limpo.

#### Ainda em aberto na monetização

Não bloqueiam o lançamento, mas estão mapeados. **Os cinco continuam abertos em
2026-08-07** — reconferidos no código, nenhum commit desde `a83bd88` mexeu
neles:

- **Trial / oferta introdutória não seria exibida.** O paywall mostra só
  `storeProduct.priceString`. No dia em que um base plan ganhar trial, o card
  vai anunciar o preço recorrente e esconder o trial — perda de conversão e
  risco de política de preço enganoso. Os dados estão em
  `storeProduct.defaultOption.freePhase/introPhase`. **Hoje não há trial
  configurado, então isso vira bloqueio só quando você ligar um.**
- **Sem botão de "tentar de novo"** na tela de "Plans are unavailable" — o único
  caminho é voltar e reabrir.
- **Sem links de Termos/Privacidade no próprio paywall** (existem no Settings).
  O Play é mais tolerante que a Apple aqui.
- **`Purchases.setLogLevel(LogLevel.debug)`** nunca é chamado. Uma linha, e
  diagnostica em segundos exatamente as duas armadilhas desta seção.
- **Gate 100% client-side**: `/api/templates/:id` é público, então o JSON
  premium é baixável sem pagar. Decisão defensável (o valor está no editor, não
  no JSON); se um dia importar, o caminho é webhook + REST API da RevenueCat.

> A configuração acima é toda **server-side**: quando ficar pronta, o app já
> instalado passa a mostrar os planos sozinho. Não precisa de novo AAB.

#### Referência

Doc oficial: https://www.revenuecat.com/docs/service-credentials/creating-play-service-credentials

#### Nomes que precisam bater exatamente

Erram silenciosamente: compila, roda, e simplesmente não desbloqueia nada.

| O quê | Valor exigido | Onde no código |
|---|---|---|
| ID do entitlement | `pro` | `entitlements.dart`, `_entitlementId` |
| Offering | precisa estar marcada como **current** | `entitlements.dart`, `packages()` lê `offerings.current` |
| Tipos de package | `$rc_monthly` e `$rc_annual` | `paywall_screen.dart`, `byType()` filtra por `PackageType` |

O terceiro é o que mais pega gente: produto anexado como package customizado em
vez do tipo padrão faz o paywall renderizar **vazio**, sem erro nenhum — cai no
mesmo estado de "sem planos".

---

## 🟡 Antes do AAB subir

### ✅ Rotas legais fora do Basic Auth (`collageweb`) — resolvido

`https://uselayer.online/privacy` e `/terms` respondiam **401** (estavam atrás
do Basic Auth que protege as páginas do editor). **Verificado em 2026-08-07:
os dois respondem 200** e servem conteúdo real — headings de política
(o que o app processa, dados no device, com quem compartilhamos, direitos,
crianças, segurança, contato) e de termos (10+ seções, incluindo a assinatura
Layer Pro). Não é 200 de tela de login.

Isso destrava as duas coisas que dependiam disso: o bot do Play consegue validar
a URL da política, e o link de Settings (`lib/src/legal.dart`, alimentado pelo
`SITE_BASE` de `env/prod.json`) abre a página em vez de um prompt de senha.

### ✅ Domínio próprio — resolvido

`env/prod.json` apontava pro host auto-gerado da Vercel
(`collageweb-iota-mu.vercel.app`), que congela dentro do APK publicado. Desde
`02a80cd` são domínios próprios:

```json
{ "API_BASE": "https://api.uselayer.online",
  "SITE_BASE": "https://uselayer.online" }
```

`API_BASE` e `SITE_BASE` continuam sendo knobs separados, então trocar de host
segue sendo duas linhas.

### Assets da ficha da loja

- [x] Ícone 512×512 — `store/icon-512.png`
- [ ] Feature graphic 1024×500
- [ ] Screenshots (mínimo 2; vale mostrar o editor e um carrossel exportado)

---

## ⚪ Durante a janela dos 14 dias

Decidido em 2026-07-28: sobem como atualização na mesma trilha, sem segurar o
primeiro upload.

- **Crash reporting** — hoje não existe nenhum. Sem isso, um tester que desinstala
  não deixa rastro. Escolha entre Sentry (só precisa de um DSN) e Firebase
  Crashlytics (casa com o Analytics abaixo, mas exige `google-services.json`).
- **Firebase Analytics** — 6 eventos já mapeados, seam no padrão do
  `EntitlementsService`. Fazer *durante* a janela evita um buraco de dados no
  dia 1 da produção, que é irrecuperável.
- **Idioma da UI** — o app é todo em inglês ("Settings", "Get Layer Pro"). Se o
  público-alvo for BR, é uma passada única no app inteiro.

> ✅ **Dúvida resolvida (2026-07-29):** trocar o binário durante a janela **não**
> reseta a contagem. O requisito do Google é sobre os 12 testers estarem
> *opt-in continuamente* por 14 dias corridos, não sobre o build ficar parado.
> Subir atualização na mesma trilha é seguro, e o plano acima está de pé.

---

## 🔧 Manutenção — depois da aprovação

Avisos de deprecação que apareceram no build. **Não mexer antes do lançamento**:
o único ganho é silenciar warning, e o risco é quebrar o build na véspera.

- AGP 8.9.1 → ≥ 8.11.1
- Kotlin 2.1.0 → ≥ 2.2.20

---

## 🚀 Gerar e subir o AAB

### Versão: sobe o versionCode, não o versionName

No Flutter os dois vivem na mesma linha do `pubspec.yaml`:

```
version: 1.0.0+1
         ^^^^^ ^
   versionName  versionCode
```

O Play rejeita **versionCode** repetido; versionName repetido não é problema. O
`1.0.0` é cosmético e pode ficar parado por vários builds. Então o próximo
upload é `1.0.0+2` — não precisa virar `1.0.1`.

> 🚧 **Isto ainda não foi feito (2026-08-07).** `pubspec.yaml` segue em
> `1.0.0+1`, e a linha nunca mudou desde o commit inicial `108263d` — o AAB que
> está na internal test é **versionCode 1**. O versionCode é único no app
> inteiro, não por trilha, então mandar o mesmo `+1` pro teste fechado é
> rejeitado no upload. **Bump antes do build final.**

> O AAB em `build/app/outputs/bundle/release/` continua sendo o de **28/07
> 14:04** e agora está **6 commits atrás**: `dc8830e`/`e040679` (resize),
> `08b57fd` (nomes de botão/assets), `a83bd88` (tratamento de erro de compra),
> `02a80cd` (URLs de produção) e `104e8a7` (nome do app → `Layer`). Ou seja:
> esse binário — e o que subiu pra internal test em 28/07 — aponta pro
> **domínio velho da Vercel** e se chama **Collage Studio**. Rebuild não é
> opcional.

### Build

```bash
cd /mnt/c/allsaas/collageapp && cmd.exe /c "flutter build appbundle --dart-define-from-file=env/prod.json"
```

Sai em `build/app/outputs/bundle/release/app-release.aab`.

> **Heap do Gradle (`02a80cd`).** `android/gradle.properties` pedia `-Xmx8G` +
> 4G de metaspace, mais RAM do que a máquina tem, e o daemon morria no meio do
> `assembleRelease` ("daemon disappeared unexpectedly"). Hoje é `-Xmx2G` / 1G de
> metaspace. Se o build voltar a morrer sem erro de compilação, é aqui que se
> olha.

⚠️ **A flag `--dart-define-from-file` não é opcional.** Sem ela o `API_BASE`
vira `localhost:3000` (app sem catálogo) e a `REVENUECAT_KEY` fica vazia (app
sem monetização). Desde 2026-07-31 isso não crasha mais o app — ver a seção de
monetização —, mas gera um AAB inútil do mesmo jeito. O `grep` abaixo é a
verificação que pega os dois casos.

### Conferir antes de subir

O gradle avisa quando a assinatura cai no debug key:

```
*** android/key.properties not found — signing release with the DEBUG key. ***
```

Se esse warning aparecer, **não suba**: o Play rejeita bundle debug-signed.

Pra confirmar que a chave de produção e as URLs entraram no binário:

```bash
python3 - <<'PY'
import zipfile
z = zipfile.ZipFile('build/app/outputs/bundle/release/app-release.aab')
lib = z.read('base/lib/arm64-v8a/libapp.so')
for label, needle in [
    ('chave prod',       b'goog_FJIAJJ'),
    ('API_BASE',         b'api.uselayer.online'),
    ('chave de TESTE',   b'test_VzAaDR'),   # tem que dar 0
    ('localhost',        b'localhost:3000'), # tem que dar 0
]:
    print(f'{label:16s} {lib.count(needle)}')
PY
```

As duas primeiras ≥ 1 e as duas últimas = 0 significa AAB de produção.

> ⚠️ **O comando antigo deste bloco estava errado** e daria falso alarme. Ele
> procurava em `base/dex/classes.dex`, mas num build de release o Dart é
> compilado AOT: as constantes de `String.fromEnvironment` vivem em
> **`base/lib/<abi>/libapp.so`**, não no dex. Grepar o dex retorna 0 mesmo num
> build perfeito. Ele também usava `unzip`, que **não está instalado no WSL
> desta máquina** (`keytool` também não) — daí a versão em `python3`.

Pra confirmar a assinatura no próprio arquivo (em vez de confiar na ausência do
warning):

```bash
python3 -c "import zipfile;open('/tmp/UPLOAD.RSA','wb').write(zipfile.ZipFile('build/app/outputs/bundle/release/app-release.aab').read('META-INF/UPLOAD.RSA'))"
openssl pkcs7 -inform DER -in /tmp/UPLOAD.RSA -print_certs -outform PEM \
  | openssl x509 -noout -subject -fingerprint -sha256
```

Tem que bater com o SHA-256 do upload keystore registrado em "✅ Já resolvido".

### Upload

1. **Teste → Teste fechado** — **não** a internal test (ver abaixo)
2. Criar nova versão → upload do `.aab`
3. Notas da versão (uma linha basta)
4. **Revisar versão → Iniciar lançamento**

O passo 4 é a armadilha que já custou uma tarde: subir o arquivo deixa o release
em **rascunho**, e rascunho não publica nada.

---

## 📋 Play Console

> Estado desta seção: **2026-07-31**. É a única parte do documento que não dá
> pra reverificar a partir do repositório — o que está marcado aqui foi feito à
> mão no console e depende de conferência lá.

> ⚠️ **Internal test não conta pros 14 dias.** O AAB está hoje na *internal
> test*, mas o requisito do Google é explicitamente **closed testing**: 12
> testers opt-in por 14 dias corridos numa trilha *fechada*. Precisa criar a
> trilha de teste fechado e mandar o AAB pra lá — o relógio só começa aí.

Feito:

- [x] Conta de desenvolvedor (US$ 25, uma vez)
- [x] App criado — **destrava o bloqueio vermelho**
- [x] Produtos de assinatura ativos + compra de teste validada no device
- [x] Ícone 512×512 — `store/icon-512.png`

Falta:

- [ ] **Trilha de teste fechado** criada e AAB enviado (a internal não serve)
- [ ] Ficha: título, descrição curta e longa, feature graphic, screenshots
- [ ] URL da política de privacidade: colar `https://uselayer.online/privacy`
      no formulário (a página **já é pública**, ver acima — falta só o campo)
- [ ] Formulário de Data safety — curto: sem login, só o que o RevenueCat coleta
      (histórico de compra + ID de device)
- [ ] Classificação de conteúdo
- [ ] Público-alvo
- [ ] Declaração de anúncios (o app não tem)
- [ ] 12 testers com opt-in, 14 dias corridos → pedir acesso à produção

---

## ✅ Já resolvido (commit `964e63b`)

Registrado pra não ser refeito por engano:

- **Assinatura de release** — `android/app/build.gradle.kts` lê
  `android/key.properties`; sem ele cai no debug key com um `logger.warn`
  explícito (antes era silencioso). Verificado no AAB: o certificado saiu de
  `CN=Android Debug` para `CN=Collage Studio` — o CN fica preso ao keystore e
  **não acompanha o rename pra `Layer`**; é interno, ninguém vê.
- **Upload keystore** — `android/upload-keystore.jks`, alias `upload`, PKCS12,
  validade até 2053. SHA-256:
  `E1:5E:F2:09:13:80:F5:D8:D3:31:AE:63:7A:3A:AC:EE:5A:63:E0:6B:35:F3:6E:97:AD:41:AC:A8:F1:0A:93:38`.
  Keystore e `key.properties` são gitignored e já têm backup fora da máquina.
- **Ícone** — a grade de colagem em paper-white sobre ink, nos tokens do
  Darkroom (sem gold, que fica reservado pra sinais de Pro). 5 mipmaps legados
  para API 24-25, adaptive icon em `mipmap-anydpi-v26` com `<monochrome>` pros
  themed icons do Android 13+, e o 512×512 da ficha.
- **Nome do app** — `android:label` de `collageapp` para `Collage Studio`, e
  depois para **`Layer`** (`104e8a7`, 04/08), junto com o `MaterialApp.title` e
  a classe raiz (`CollageApp` → `LayerApp`) em `lib/main.dart`. **`Layer` é o
  nome atual** — é ele que tem que ir no título da ficha da loja e é ele que
  aparece na UI (`Get Layer Pro`, no Settings) e nas páginas legais
  ("Privacy Policy · Layer"). "Collage Studio" só sobrevive em comentário de
  código (`model/template.dart`), no CN do keystore e no ID do produto de
  assinatura no Play (`collage_pro`) — os três imutáveis ou invisíveis pro
  usuário.
- **Erro da galeria** — `gallery_screen.dart` não mostra mais a exception crua;
  a mensagem virou acionável e o erro técnico vai pro `debugPrint`.
- **Links legais** — seção "Legal" no Settings via `url_launcher`, com o intent
  `VIEW`/`https` declarado no `<queries>` do manifest (senão o package
  visibility do Android 11+ engole o launch).

Estado do build no commit: `flutter analyze` limpo, **245 testes passando**, AAB
de 56 MB gerando ~12 MB de download real por aparelho (o resto são símbolos de
debug, que ficam no Play e não descem pro device).
