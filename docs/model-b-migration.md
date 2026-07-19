# Design: migração para o "Modelo B" (canvas contínuo + camada slide-aware)

Status: **proposta / RFC** — não implementado.
Contexto: discussão sobre como o app lida com carrosséis multi-painel e
imagens panorâmicas ("seamless").

## TL;DR

Hoje o app modela cada slide como um canvas independente (`Template.panels[]`)
e usa uma **sangria (bleed)** — um eco cosmético — para dar a impressão de que
uma imagem atravessa slides. Uma layer sempre **pertence a um único painel**.
Esse híbrido não é nem "slides independentes" nem "panorâmica costurada" — é a
raiz de uma classe de bugs de ambiguidade.

O Modelo B troca isso por uma **arquitetura em duas camadas**:

1. **Dados: um canvas contínuo** (`slideCount × slideWidth`) onde as layers
   vivem num **único sistema de coordenadas**. "Slides" são apenas **linhas de
   corte**; o fatiamento acontece no **export**.
2. **UX: uma camada slide-aware** por cima do canvas contínuo — snap às linhas
   de corte, fundo por slide, e reordenar/apagar slide movendo o conteúdo
   daquele slide **como um grupo**.

**O ponto que fecha a decisão:** o canvas contínuo é um **superset**. Slide
independente é o *caso degenerado* de B (nada atravessa a linha de corte, fundo
vem de `slideBackgrounds[i]`); panorâmica é uma layer com `x` atravessando
cortes. É por isso que os apps de referência (SCRL, Unfold) entregam **os dois**
casos de uso sobre o mesmo modelo — canvas contínuo embaixo, UX slide-aware em
cima. Não é escolher A *ou* B; B faz os dois, A não faz seamless.

**Amarra principal:** este app é o renderizador do schema do editor web
(`collageweb`). Qualquer mudança de schema tem que ser **coordenada com os dois
repositórios** e preservar o round-trip WYSIWYG.

---

## Motivação

O modelo atual acopla o conteúdo a um painel enquanto ele é visível em vários.
Desse acoplamento nasce uma classe recorrente de bugs de ambiguidade:

- **"Qual painel representa o documento?"** — o thumbnail da tela de projetos
  renderizava fixamente `panels.first`, que em docs multi-painel costuma ficar em
  branco (o conteúdo vai pro painel em foco, que é o recém-adicionado). Corrigido
  como paliativo em `projects_screen.dart` (mostra o primeiro painel *com
  conteúdo*), mas é sintoma do modelo.
- **Reordenar/apagar painel quebra a panorâmica silenciosamente** — a sangria é
  posicional (deslocada por exatamente uma largura de canvas). Inserir um slide no
  meio desloca tudo.
- **Alinhar a emenda é manual** — para uma panorâmica sem emenda, o usuário
  posiciona a imagem num painel e "chuta" o transbordo pro vizinho olhando o
  fantasma. Não existe o conceito de "esta imagem ocupa os slides 1–3".

### O que o mercado faz — e por que ambos entregam "os dois"

| App | Modelo de dados | Slides independentes | Panorâmica costurada |
|---|---|---|---|
| SCRL | Canvas contínuo (B) | Sim (nada cruza o corte) | First-class, é o produto |
| Panoslice / PanoSplit | Canvas contínuo + auto-slice (B) | Sim | First-class |
| Unfold | Canvas contínuo + UX de páginas | Sim (uso central) | Sim (imagem atravessa) |

O ponto revisto: **ninguém resolve "os dois" com um híbrido de dados**. Todos
rodam um **canvas contínuo** e diferenciam os dois usos numa **camada de UX** por
cima (snap, páginas, reorder). O híbrido atual do nosso app — "layer pertence a
um painel mas ecoa no vizinho" — é justamente o modelo que *nenhum* deles usa,
porque não é nem uma coisa nem outra.

---

## Modelo A (atual) vs. Modelo B

- **Modelo A** — slides independentes de `slideWidth × slideHeight`; layer
  pertence a um painel; sangria echoa o transbordo no vizinho; export = um
  `RepaintBoundary` por painel. **Não representa seamless de verdade.**
- **Modelo B** — um canvas contínuo de `slideCount × slideWidth` (+ gutters);
  layers em coordenadas contínuas; slides são linhas de corte; export fatia o
  canvas. Uma **camada slide-aware** dá de volta tudo que era bom no A (páginas,
  fundo por slide, reorder) sem o bleed. **Superset de A.**

---

## Schema (v4)

Bump `kSupportedSchemaVersion` 3 → 4, mantendo leitura de v ≤ 3. **v4 tem que ser
autorado no `collageweb`** (`lib/template/types.ts`); este app apenas o interpreta.

**Antes (v3):**
```jsonc
{
  "schemaVersion": 3,
  "canvas": { "width": 1080, "height": 1920 },
  "panels": [
    { "id": "p0", "backgroundColor": "#FFF", "layers": [ /* x,y locais ao painel */ ] },
    { "id": "p1", "backgroundColor": "#EEE", "layers": [ ... ] }
  ]
}
```

**Depois (v4):**
```jsonc
{
  "schemaVersion": 4,
  "canvas": {
    "slideWidth": 1080,
    "slideHeight": 1920,
    "slideCount": 3,
    "gutter": 0
  },
  "slideBackgrounds": ["#FFF", "#EEE", "#FFF"],
  "layers": [ /* x,y em coordenadas CONTÍNUAS: 0 .. slideCount*slideWidth */ ]
}
```

Ponto-chave: `layers[]` num espaço contínuo. Uma imagem panorâmica é **uma
layer** com `x=0, width=3240` — some o conceito de "pertence ao painel X".
`slideBackgrounds` é o único dado naturalmente por-slide.

> Nota: uma layer **não** carrega `slideIndex`. A qual slide ela pertence é
> derivado da geometria (`x`/`width` vs. as linhas de corte) — é o que mantém o
> modelo de dados um superset limpo. A camada slide-aware (abaixo) só *consulta*
> essa derivação; nunca a persiste.

---

## A camada slide-aware (o que torna B capaz de fazer "os dois")

O canvas contínuo é o modelo de dados. Sozinho, ele faz seamless de graça, mas o
uso "páginas independentes" ficaria cru (reordenar seria mexer em `x` na mão).
A camada slide-aware é um **conjunto de helpers derivados + comportamentos de
editor** que dá a sensação de "slides" sem reintroduzir slides nos dados.

### Derivações puras (sem estado novo)

```dart
extension SlideAware on Document {
  // A qual slide o centro da layer cai (para reorder/delete "por slide").
  int slideOf(Layer l) =>
      ((l.x + l.width / 2) ~/ (slideWidth + gutter)).clamp(0, slideCount - 1);

  // Layers cujo centro está no slide i — a "página" i como grupo.
  Iterable<Layer> layersInSlide(int i) => layers.where((l) => slideOf(l) == i);

  // Layer atravessa mais de um slide? (panorâmica de fato)
  bool spansSlides(Layer l) => slideOf(l) != slideOf(l.copyWith(x: l.x + l.width));
}
```

### Comportamentos (todos vivem no editor, não nos dados)

- **Snap às linhas de corte.** Ao arrastar/soltar uma layer perto de uma borda de
  slide, gruda no corte (`slideRect(i).left/right`). Dá alinhamento de página sem
  esforço; quem quer panorâmica só arrasta atravessando o corte (o snap ajuda a
  encostar as bordas de duas layers na mesma linha).
- **Reordenar slide = mover um grupo.** "Trocar slide 2 ↔ 1" pega
  `layersInSlide(2)`, desloca seu `x` em `−(slideWidth+gutter)`, e o slide 1 no
  sentido oposto; `slideBackgrounds` troca de índice junto. Layers que
  **atravessam** o corte (`spansSlides`) não entram no grupo — a UI avisa
  ("este item cruza slides") em vez de rasgá-lo. Resolve o "chato" do reorder que
  o tradeoff antigo apontava.
- **Apagar slide.** Remove `layersInSlide(i)` (ou oferece "mover conteúdo pro
  vizinho"), decrementa `slideCount`, reflow do `x` dos slides à direita.
- **Adicionar slide.** Incrementa `slideCount`, `slideBackgrounds.add(...)`;
  nada mais reflui (cresce à direita).
- **Fundo por slide na UI.** O picker de cor de fundo opera sobre
  `slideBackgrounds[slideAtras da viewport atual]` — o usuário sente "cada slide
  tem seu fundo" mesmo com um único documento.
- **Modo de foco (opcional).** O editor pode centralizar/emoldurar um slide por
  vez (sensação "página") mesmo o canvas sendo contínuo — é só um viewport
  transform, não muda dados.

O contrato: **a camada slide-aware nunca escreve `slideIndex` numa layer**. Ela
lê geometria e edita `x`/`slideBackgrounds`/`slideCount`. Isso mantém o modelo
um superset — panorâmica e páginas convivem no mesmo `layers[]`.

---

## Modelo no app (Dart)

```dart
class Document {                 // substitui o uso de Template.panels
  final double slideWidth, slideHeight, gutter;
  final int slideCount;
  final List<Color> slideBackgrounds;  // len == slideCount
  final List<Layer> layers;            // coordenadas contínuas

  double get contentWidth =>
      slideCount * slideWidth + (slideCount - 1) * gutter;

  Rect slideRect(int i) =>             // região do slide i no espaço contínuo
      Rect.fromLTWH(i * (slideWidth + gutter), 0, slideWidth, slideHeight);
}
```

`SlotContent` quase não muda — overrides continuam keyed por `slotId`. O que some:

- `addedLayers` (Map por painel) → só `layers` adicionadas ao documento.
- `addedPanels` → "aumentar `slideCount`".
- `layerOrders` / `panelBackgrounds` por-painel → ordem global + `slideBackgrounds`.

---

## Render

- `PanelCanvas` (1 painel) → `CanvasView` que renderiza **o canvas inteiro uma
  vez**.
- **Some a sangria inteira** (`panelBefore` / `panelAfter` / `_bleed`) — a layer
  simplesmente atravessa.
- Editor mostra o canvas contínuo com **guias tracejadas** nas linhas de corte
  (`slideRect(i)`) — as guias também são os alvos de snap da camada slide-aware.
- **Thumbnail**: renderiza o canvas inteiro reduzido (ou o viewport do slide 0).
  A ambiguidade "qual painel mostrar" desaparece — era a raiz do bug do thumbnail.

---

## Export (o coração do Modelo B)

Hoje: um `RepaintBoundary` por painel (`export.dart`). Depois: renderiza o canvas
contínuo e **fatia** — para cada slide `i`, captura o viewport `slideRect(i)`:

```dart
for (var i = 0; i < doc.slideCount; i++) {
  final png = await capturePngRegion(canvasKey, doc.slideRect(i));
  // uma imagem por slide, alinhadas por construção (mesmo raster contínuo)
}
```

Alinhamento perfeito de graça: as fatias vêm do mesmo raster.

> **Spike FEITO — resolvido, caminho (b) validado.** No Flutter,
> `RepaintBoundary.toImage()` captura o boundary **inteiro**, não um
> sub-retângulo. O spike provou que dá pra **capturar o canvas contínuo uma vez
> e cropar cada slide com puro `dart:ui`** (`PictureRecorder` +
> `Canvas.drawImageRect`) — sem o package `image`, GPU-backed, dimensões e
> pixels exatos. Testado em 1:1 e em resolução de export alta via `pixelRatio`
> (canvas renderizado minúsculo na tela, exportado a 1080/slide). Corpo
> candidato do `capturePngRegion`:
>
> ```dart
> Future<ui.Image> capturePngRegion(ui.Image full, Rect region) async {
>   final recorder = ui.PictureRecorder();
>   final canvas = Canvas(recorder);
>   canvas.drawImageRect(full, region,               // region em pixels do raster
>       Rect.fromLTWH(0, 0, region.width, region.height),
>       Paint()..filterQuality = FilterQuality.high);
>   return recorder.endRecording().toImage(
>       region.width.round(), region.height.round());
> }
> ```
>
> **Fórmula de produção:** captura o boundary contínuo com
> `pixelRatio = targetSlideWidth / slideWidthLogical` (igual ao `capturePng`
> de hoje); os rects de corte vivem no espaço de pixels da imagem capturada,
> escalados pelo mesmo `pixelRatio` (`i * slideW * ratio`, largura
> `slideW * ratio`). O caminho (a) — N viewports — fica descartado; não é
> necessário.
>
> **Custo de memória (transiente, aceitável):** o raster contínuo é uma
> `ui.Image` só. 3×1080×1920 RGBA ≈ 25 MB; 10 slides ≈ 83 MB — grande mas
> transitório e descartado após o fatiamento. Não é bloqueio.

---

## Migração dos projetos salvos (`project.json`)

Determinística, no `ProjectStore.load` quando `schemaVersion` for antigo:

```
para cada painel i (template.panels + content.addedPanels):
   offsetX = i * (slideWidth + gutter)
   para cada layer do painel: layer.x += offsetX  → joga no layers[] global
   slideBackgrounds[i] = panelBackground(i)
slideCount = nº de painéis
```

Overrides (`offsets`, `scales`, `rotations`, …), keyed por `slotId`, sobrevivem
intactos. Um projeto A migrado cai naturalmente no caso degenerado (nada cruza
corte) — a camada slide-aware o trata como "N páginas independentes" sem esforço.

---

## O que sai / simplifica vs. o que entra

**Sai/simplifica:** sangria inteira, `effectivePanel`, `addedLayers` /
`addedPanels` por-painel, `_focusedPanelId` ambíguo, thumbnail com heurística de
"primeiro painel com conteúdo", export por-painel.

**Entra:** conceito de `Document` contínuo, guias de corte no editor, **camada
slide-aware** (derivações `slideOf`/`layersInSlide`/`spansSlides` + snap, reorder
por grupo, add/remove slide, fundo por slide), migração v3→v4.

---

## Tradeoff honesto (revisto)

O tradeoff antigo dizia que reordenar/designs independentes ficam "chatos" no B.
Com a camada slide-aware, isso muda de figura:

- **Reordenar slides** — deixa de ser "mexer em `x` na mão". Vira "mover
  `layersInSlide(i)` como grupo + trocar `slideBackgrounds`". É a mesma coisa que
  SCRL/Unfold fazem; **problema resolvido**, não uma parede. O único caso que
  exige decisão de UX é a layer que **atravessa** o corte durante um reorder — e a
  resposta é avisar, não rasgar.
- **Designs por-slide independentes** — o caso degenerado do canvas contínuo. Com
  fundo por slide na UI + modo de foco, a sensação "cada slide é seu mundo" volta
  sem o bleed.

**O que sobra de custo real:** a camada slide-aware é **trabalho de editor** (a
maior fatia do esforço migrou pra lá, ver fases 4–5). Ela não é gratuita — mas é
código localizado e determinístico, não risco de produto.

**Decisão:** com "os dois" como requisito confirmado, não há mais bifurcação —
**B + camada slide-aware é o caminho**. "A limpo" morre (não faz seamless); o
híbrido atual morre (não faz nem um nem outro).

---

## Plano em fases

1. **Definir schema v4** no `collageweb` (`types.ts`) e no app em paralelo — nada
   muda pro usuário ainda. *Amarra: os dois repos.*
2. **App lê v3 e v4** (dual), com migração v3→v4 no load. Render novo
   (`CanvasView`) atrás do schema.
3. **Export por fatiamento** (validar com o spike acima) + thumbnail do canvas
   contínuo.
4. **Editor app**: canvas contínuo + guias de corte + **camada slide-aware**
   (snap, reorder por grupo, add/remove slide, fundo por slide).
5. **Editor web** autora v4 + camada slide-aware equivalente; rollout gated por
   `schemaVersion`.

**Esforço realista: ~3 semanas de trabalho focado.** Render e export no app são
localizados (`template_canvas.dart`, `export.dart`). O peso migrou pra **camada
slide-aware nos editores** (fases 4–5, topo das faixas) e pra **coordenação do
schema + round-trip WYSIWYG entre os dois repos** — este é o gargalo real; sem
ele, o app não pode migrar sozinho.

| Fase | Escopo | Esforço |
|---|---|---|
| 1. Schema v4 (web + app dual read) | tipos, sem UI | ~1–2 dias |
| 2. Migração v3→v4 no load | reflow determinístico | ~1–2 dias |
| 3. Render app + export por fatiamento | + spike do capture | ~3–4 dias |
| 4. Editor app slide-aware | snap/reorder/fundo/slides | ~4–5 dias |
| 5. Editor web autora v4 + slide-aware | Konva contínuo | ~4–5 dias |

---

## Ordenação com o schema de grades (grids) — DECIDIDO

**Grids primeiro (v3), Modelo B depois (v4).** Motivos:

1. **Time-to-value** — grids é table-stakes e auto-contido (~1–2 sessões); B são
   ~3 semanas fundacionais. Não enterrar uma feature pronta atrás do encanamento.
2. **Risco na ordem certa** — o pequeno e contido antes do grande que reescreve
   o editor inteiro.
3. **Acoplamento de migração ~zero** — `GridLayer` é só uma layer com `x`/`width`;
   a migração v3→v4 já reflui todas as layers uniformemente, então o grid pega
   carona sem código especial.

**Guardrails (obrigatórios pra essa ordem ser segura):**

- Grids **não** introduz estado novo por-painel que o B tenha que desfazer. O
  plano de grids já está limpo: slotIds de célula globais (`nextSlotId` varre
  todos os painéis), `gridOverrides` keyed por `gridLayerId` global.
- **Este plano (Modelo B) tem que preservar `GridLayer`:** a migração v3→v4
  reflui o `x` do grid como o de qualquer layer; o novo `CanvasView` precisa de
  `case "grid"` no render; o export por fatiamento trata um grid que cruza a
  linha de corte como qualquer layer (renderiza através, é fatiado).
- **Custo residual:** a cola de editor do grid (botão Toolbar, `case "grid"` em
  `PropertiesPanel` e no switch de render) é construída no editor A e
  re-verificada no editor B. Pequeno — o peso do grid (`cellRect`, presets,
  `GridNode`, `validate`) é agnóstico de coordenada e porta intacto.

---

## Arquivos afetados (app)

- `lib/src/model/template.dart` — novo `Document`/canvas contínuo; `fromJson` dual v3/v4.
- `lib/src/model/slot_content.dart` — remover `addedLayers`/`addedPanels` por-painel; ordem global.
- `lib/src/model/slide_aware.dart` *(novo)* — derivações `slideOf`/`layersInSlide`/`spansSlides`.
- `lib/src/rendering/template_canvas.dart` — `PanelCanvas` → `CanvasView`; remover sangria.
- `lib/src/rendering/export.dart` — export por fatiamento de viewport.
- `lib/src/screens/template_screen.dart` — editor contínuo + guias de corte + camada slide-aware.
- `lib/src/screens/projects_screen.dart` — thumbnail do canvas contínuo (remove heurística).
- `lib/src/api/project_store.dart` — migração v3→v4 no `load`.

## Arquivos afetados (web — `collageweb`)

- `lib/template/types.ts` — schema v4 (canvas contínuo, `slideBackgrounds`); `CURRENT_SCHEMA_VERSION`.
- `lib/template/factory.ts` / `validate.ts` — autoria v4 + gate por `schemaVersion`.
- `components/editor/canvas/CanvasStage.tsx` — canvas contínuo, guias de corte, snap.
- `store/editorStore.ts` — ações slide-aware (reorder por grupo, add/remove slide, fundo por slide).
