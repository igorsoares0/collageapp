# Checklist de lançamento — Google Play (teste fechado)

Estado em **2026-07-28**, depois do commit `964e63b` ("prepare to play").

Escopo: **só Android**. iOS está fora — o projeto nunca foi buildado pra iOS e
o desenvolvimento acontece em Windows/WSL, onde nada de iOS é verificável.

## TL;DR

**Não há mais bloqueio de código.** O último era a chave de Test Store do
RevenueCat, que crashava o app em release; ela virou variável de build e
`env/prod.json` ship com monetização desligada, então o AAB de produção já sobe
e abre. O que sobra é configuração de Play Console e as páginas legais no
`collageweb`.

O relógio dos **12 testers / 14 dias** só começa a contar quando o primeiro AAB
estiver na trilha de teste fechado. Calendário é o recurso escasso aqui, código
não. Por isso a regra de bolso deste documento: **o que não impede o AAB de
subir, sobe depois, durante a janela.**

---

## 🟠 Monetização — o app abre, mas ninguém consegue pagar

### Chave do RevenueCat

O SDK nativo do RevenueCat **rejeita uma chave de Test Store em build não-debug**
e a rejeição não passa pelo `try/catch` do Dart — o app morria antes de pintar a
primeira tela. Não é um bug a corrigir: é a proteção do RevenueCat contra
publicar com chave de teste.

**Já mitigado:** a chave virou `REVENUECAT_KEY`, variável de build lida de
`env/*.json` (`lib/src/api/entitlements.dart`), e `env/prod.json` ship com ela
**vazia** — o SDK não é configurado, todo mundo fica free, o paywall mostra
"plans unavailable" e nada crasha. **O build de produção já sobe hoje.**

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

Falta terminar:

1. **Products** → importar `collage_pro:monthly` e `collage_pro:annual`
2. **Entitlements** → id **`pro`** → anexar os dois
3. **Offerings** → `default` → **Make current** → packages **Monthly** e **Annual**
4. Play Console → *Configurações → Teste de licença* → e-mails dos testers
5. Testar ponta a ponta: paywall com os dois planos em BRL → compra → badge Pro
   → reinstalar → **Restore purchases** devolve o Pro

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

### Rotas legais fora do Basic Auth (`collageweb`)

`https://<site>/privacy` e `/terms` respondem **401** hoje — estão atrás do
Basic Auth que protege as páginas do editor.

Precisa das duas coisas: as páginas existirem **e** serem públicas. O Play valida
a URL da política automaticamente (bot, sem credencial), e o link novo em
Settings cairia numa tela de login. Trabalho no repositório `collageweb`.

O app já aponta pra lá: `lib/src/legal.dart`, alimentado pelo `SITE_BASE` de
`env/prod.json`.

### Domínio próprio

`env/prod.json` aponta pra `collageweb-iota-mu.vercel.app` — domínio
auto-gerado da Vercel. A URL **congela dentro do APK publicado**: se o projeto
for renomeado ou o deploy duplicado for limpo, todo build já instalado quebra e
só conserta com uma nova versão na loja.

`API_BASE` e `SITE_BASE` são knobs separados justamente pra isso — trocar são
duas linhas.

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
- **Idioma da UI** — o app é todo em inglês ("Settings", "Get Collage Pro"). Se o
  público-alvo for BR, é uma passada única no app inteiro.

> ⚠️ **Verificar antes:** trocar o binário durante a janela mexe na contagem dos
> 14 dias? Nunca foi confirmado no Play Console. Errar aí custa 14 dias e
> derruba o plano acima.

---

## 🔧 Manutenção — depois da aprovação

Avisos de deprecação que apareceram no build. **Não mexer antes do lançamento**:
o único ganho é silenciar warning, e o risco é quebrar o build na véspera.

- AGP 8.9.1 → ≥ 8.11.1
- Kotlin 2.1.0 → ≥ 2.2.20

---

## 📋 Play Console

- [ ] Conta de desenvolvedor (US$ 25, uma vez)
- [ ] App criado — **destrava o bloqueio vermelho**
- [ ] Produtos de assinatura ativos + license testers
- [ ] Ficha: título, descrição curta e longa, ícone, feature graphic, screenshots
- [ ] URL da política de privacidade (pública, ver acima)
- [ ] Formulário de Data safety — curto: sem login, só o que o RevenueCat coleta
      (histórico de compra + ID de device)
- [ ] Classificação de conteúdo
- [ ] Público-alvo
- [ ] Declaração de anúncios (o app não tem)
- [ ] Trilha de teste fechado criada e AAB enviado
- [ ] 12 testers com opt-in, 14 dias corridos → pedir acesso à produção

---

## ✅ Já resolvido (commit `964e63b`)

Registrado pra não ser refeito por engano:

- **Assinatura de release** — `android/app/build.gradle.kts` lê
  `android/key.properties`; sem ele cai no debug key com um `logger.warn`
  explícito (antes era silencioso). Verificado no AAB: o certificado saiu de
  `CN=Android Debug` para `CN=Collage Studio`.
- **Upload keystore** — `android/upload-keystore.jks`, alias `upload`, PKCS12,
  validade até 2053. SHA-256:
  `E1:5E:F2:09:13:80:F5:D8:D3:31:AE:63:7A:3A:AC:EE:5A:63:E0:6B:35:F3:6E:97:AD:41:AC:A8:F1:0A:93:38`.
  Keystore e `key.properties` são gitignored e já têm backup fora da máquina.
- **Ícone** — a grade de colagem em paper-white sobre ink, nos tokens do
  Darkroom (sem gold, que fica reservado pra sinais de Pro). 5 mipmaps legados
  para API 24-25, adaptive icon em `mipmap-anydpi-v26` com `<monochrome>` pros
  themed icons do Android 13+, e o 512×512 da ficha.
- **Nome do app** — `android:label` de `collageapp` para `Collage Studio`.
- **Erro da galeria** — `gallery_screen.dart` não mostra mais a exception crua;
  a mensagem virou acionável e o erro técnico vai pro `debugPrint`.
- **Links legais** — seção "Legal" no Settings via `url_launcher`, com o intent
  `VIEW`/`https` declarado no `<queries>` do manifest (senão o package
  visibility do Android 11+ engole o launch).

Estado do build no commit: `flutter analyze` limpo, **245 testes passando**, AAB
de 56 MB gerando ~12 MB de download real por aparelho (o resto são símbolos de
debug, que ficam no Play e não descem pro device).
