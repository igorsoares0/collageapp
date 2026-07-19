# Design: migração para o "Modelo B" (canvas contínuo)

Status: **proposta / RFC** — não implementado.
Contexto: discussão sobre como o app lida com carrosséis multi-painel e
imagens panorâmicas ("seamless").

## TL;DR

Hoje o app modela cada slide como um canvas independente (`Template.panels[]`)
e usa uma **sangria (bleed)** — um eco cosmético — para dar a impressão de que
uma imagem atravessa slides. Uma layer sempre **pertence a um único painel**.

O Modelo B troca isso por **um canvas contínuo** (`slideCount × slideWidth`)
onde as layers vivem num **único sistema de coordenadas**. "Slides" viram apenas
**linhas de corte**; o fatiamento acontece no **export**. É o modelo que os apps
seamless-first do mercado usam (SCRL, Panoslice, PanoSplit).

**Amarra principal:** este app é o renderizador do schema do editor web
(`collageweb`). Qualquer mudança de schema tem que ser **coordenada com os dois
repositórios** e preservar o round-trip WYSIWYG.

---

## Motivação

O modelo atual acopla o conteúdo a um painel enquanto ele é visível em vários.
Desse desacoplamento nasce uma classe recorrente de bugs de ambiguidade:

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

### O que o mercado faz

| App | Modelo | Panorâmica costurada |
|---|---|---|
| SCRL | Canvas contínuo (B) | First-class, é o produto |
| Panoslice / PanoSplit | Canvas contínuo + auto-slice (B) | First-class |
| Unfold | Per-slide / template (A) | Secundário (via template) |

Ninguém que leva seamless a sério usa o híbrido atual ("layer pertence a um
painel mas aparece em vários"). Ou a imagem vive no espaço contínuo (B), ou cada
slide é uma peça independente (A) — sem sangria.

---

## Modelo A (atual) vs. Modelo B

- **Modelo A** — slides independentes de `slideWidth × slideHeight`; layer
  pertence a um painel; sangria echoa o transbordo no vizinho; export = um
  `RepaintBoundary` por painel.
- **Modelo B** — um canvas contínuo de `slideCount × slideWidth` (+ gutters);
  layers em coordenadas contínuas; slides são linhas de corte; export fatia o
  canvas.

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
  (`slideRect(i)`).
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
intactos.

---

## O que sai / simplifica vs. o que entra

**Sai/simplifica:** sangria inteira, `effectivePanel`, `addedLayers` /
`addedPanels` por-painel, `_focusedPanelId` ambíguo, thumbnail com heurística de
"primeiro painel com conteúdo", export por-painel.

**Entra:** conceito de `Document` contínuo, guias de corte no editor, gestão de
`slideCount` (add/remove slide = mudar contagem + reflow), migração v3→v4.

---

## Tradeoff honesto (onde B fica pior)

No Modelo A, **painel é uma unidade reordenável de primeira classe**. No B, slide
é só uma região de corte. Então:

- **Reordenar slides** = reflow de coordenadas `x`. Ótimo pra panorâmica, chato
  pra "10 páginas independentes" (mover a página 5 pra posição 2 empurra tudo).
- **Designs por-slide totalmente independentes** (fundos diferentes, nada
  atravessando) ficam menos naturais — existe `slideBackgrounds`, mas "cada slide
  é seu mundo" era mais limpo no A.

**Decisão:** B é certo se panorâmica/seamless for o uso central. Se o app for
mais "coleção de templates por página", o A limpo (sem sangria) é melhor. Ter os
dois 100% exigiria um modelo híbrido de "seções", que reintroduz complexidade.

---

## Plano em fases

1. **Definir schema v4** no `collageweb` (`types.ts`) e no app em paralelo — nada
   muda pro usuário ainda. *Amarra: os dois repos.*
2. **App lê v3 e v4** (dual), com migração v3→v4 no load. Render novo
   (`CanvasView`) atrás do schema.
3. **Export por fatiamento** + thumbnail do canvas contínuo.
4. **Editor**: canvas contínuo + guias de corte; add/remove slide.
5. **Editor web** autora v4; rollout gated por `schemaVersion`.

**Esforço realista:** médio-grande. Render e export no app são localizados
(`template_canvas.dart`, `export.dart`) — ~1 sprint no app. O gargalo é a
**coordenação com o `collageweb` + schema + round-trip WYSIWYG**; sem isso, o app
não pode migrar sozinho.

---

## Arquivos afetados (app)

- `lib/src/model/template.dart` — novo `Document`/canvas contínuo; `fromJson` dual v3/v4.
- `lib/src/model/slot_content.dart` — remover `addedLayers`/`addedPanels` por-painel; ordem global.
- `lib/src/rendering/template_canvas.dart` — `PanelCanvas` → `CanvasView`; remover sangria.
- `lib/src/rendering/export.dart` — export por fatiamento de viewport.
- `lib/src/screens/template_screen.dart` — editor contínuo + guias de corte; `slideCount`.
- `lib/src/screens/projects_screen.dart` — thumbnail do canvas contínuo (remove heurística).
- `lib/src/api/project_store.dart` — migração v3→v4 no `load`.
