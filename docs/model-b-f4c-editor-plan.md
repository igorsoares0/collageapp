# Modelo B — F4c: converter o editor para o canvas contínuo

Status: **IMPLEMENTADO** (`2026f48 edit on the continuous canvas`), seguido de
`75e4e53 add slide reorder and delete` e da cauda de correções em cima
(`6cffd5c` zoom out, `bbc2dc3` drift do dot do carrossel, `6acb79f` story à
esquerda, `15fdd13`/`0447969` resize, `36980a3` layers).
Contexto: `docs/model-b-migration.md` (RFC).

O que segue é o plano **como foi escrito antes da execução**, mantido como
registro. O que de fato saiu diferente está em [§9 Resultado](#9-resultado).

## Por que este passo é diferente

É o único da migração **sem ponto de parada que compile**. Estado, histórico, save,
os sites de mutação, o build do canvas, o export e a folha de layers mudam juntos.
Executar do início ao fim numa sessão, ou não começar.

## Pré-requisitos (prontos, testados, commitados)

| Peça | Onde |
|---|---|
| Modelo `Document` + derivações | `lib/src/model/template.dart`, `slide_aware.dart` |
| Migração v3→v4 | `lib/src/model/migrate_v4.dart` |
| Operações de slide | `lib/src/model/slide_ops.dart` |
| Renderer contínuo editável | `CanvasView` em `lib/src/rendering/template_canvas.dart` |
| Export fatiado | `capturePngSlices` em `lib/src/rendering/export.dart` |
| Leitura dual + gravação v4 | `ProjectStore.loadAsDocument` / `saveDocument` |

## Alvo

`lib/src/screens/template_screen.dart` — 2034 linhas, ~141 referências a painel.

---

## 1. Estado

```dart
// SAI
late Future<Template> _template;
Template? _resolvedTemplate;
String? _focusedPanelId;
final Map<String, GlobalKey> _panelKeys = {};
final List<SlotContent> _undoStack = [];
final List<SlotContent> _redoStack = [];

// ENTRA
Document _document;                    // estrutura
SlotContent _content;                  // overrides por slot (inalterado)
final GlobalKey _canvasKey = GlobalKey();   // UM boundary, não um por painel
final List<_Snapshot> _undoStack = [];
final List<_Snapshot> _redoStack = [];

typedef _Snapshot = ({Document doc, SlotContent content});
```

**`_focusedPanelId` MORRE.** O slide em foco é derivado:
`_focusedSlide => _selectedSlot != null ? _document.slideOf(layerOf(_selectedSlot)) : 0`.
Todos os `_focusedPanelId = panel.id;` espalhados pelos callbacks somem — eram
bookkeeping que o modelo contínuo torna desnecessário.

## 2. Histórico

`_record()` empilha `(doc: _document, content: _content)`.
`_restore(snapshot)` restaura os dois.
`_edit(SlotContent)` continua para edições só-de-overrides (a maioria: drag,
scale, rotate, texto, cor, fonte) — o doc não muda.
Novo `_editDoc(Document)` para edições estruturais.

**Cuidado:** a coalescência (`_editRunKey`) deve continuar funcionando igual —
ela é o que faz um drag inteiro virar um passo de undo.

## 3. Save

```dart
store.saveDocument(ContinuousProject(
  id: _projectId ??= _newProjectId(),
  name: _document.name,
  updatedAt: DateTime.now(),
  document: _document,
  content: _content,
  migrated: false,
));
```

## 4. Sites de mutação (o grosso)

| Hoje | Vira |
|---|---|
| `_content.withAddedLayer(panel.id, layer)` | `addLayerToSlide(_document, slide, layer)` |
| `_content.withAddedPanel(panel)` | `addSlide(_document)` |
| `_content.withPanelBackground(id, color)` | `setSlideBackground(_document, i, color)` |
| `_content.withLayerOrder(panelId, ids)` | reordenar `_document.layers` |
| `_panels(template)` | `_document.slideCount` / `layersInSlide(i)` |
| `_focusedPanel(template)` | `_focusedSlide` (int) |
| `_effectivePanel(p)` | — (some: não há overlay estrutural) |
| `_allLayers(template)` | `_document.layers` |

**A construção das layers NÃO muda.** `x: (canvasWidth - width)/2` já é local do
slide, e `addLayerToSlide` converte para contínuo. Não fazer aritmética de pitch
nos call sites — é a armadilha nº 1 (ver §7).

## 5. Build do canvas

Substituir o `Row` de `PanelCanvas` (linhas ~1618-1700) por **um** `CanvasView`
dentro da superfície com zoom:

```dart
CanvasView(
  exportKey: _canvasKey,
  document: _document,
  content: _content,
  fontResolver: widget.fontResolver,
  assetCatalog: _catalog,
  showCutGuides: true,          // editor mostra as linhas de corte
  guideXs: _guideXs, guideYs: _guideYs,
  selectedSlotId: _selectedSlot,
  editingSlotId: _editingSlot,
  // ...mesmos callbacks de hoje, SEM os `_focusedPanelId = panel.id`
)
```

O cálculo de `sidePad`/`innerWidth` (centralização do Story) some — há um só
canvas de `contentWidth`, então o `FittedBox` do `CanvasView` resolve.

## 6. Export

`_capturePanels` vira:
```dart
final shots = await capturePngSlices(_canvasKey, _document,
    targetSlideWidth: _document.slideWidth);
```
Uma captura, N fatias, emendas alinhadas por construção. O `_panelKeys` some.
A ordem de gravação na galeria (painel 1 gravado por ÚLTIMO) **continua valendo** —
ver `_saveToGallery` e a memória `carousel-bleed` / o fix de DATE_TAKEN.

## 7. Armadilhas conhecidas

1. **`x` do slide vs. `x` do documento.** Não dá erro de compilação misturar os
   dois. Já me mordeu escrevendo teste (`x=2010` num doc de 900 de largura).
   Regra: call sites pensam em coordenada LOCAL do slide; só `slide_ops` converte.
2. **Undo/redo agora versiona duas coisas.** Um snapshot que só guarde o content
   perde estrutura silenciosamente (adicionar slide viraria irreversível).
3. **`layers_test.dart` é o único teste panel-coupled** (19 referências) — vai
   precisar acompanhar. Os outros 7 arquivos do editor testam comportamento
   visível (0-6 referências) e devem passar SEM alteração. **Se eles quebrarem, é
   regressão de verdade, não teste desatualizado** — esse é o sinal mais valioso
   da conversão.
4. **`projects_screen.dart:71`** (`_openProject`) ainda usa `load()` clássico;
   precisa virar `loadAsDocument` no mesmo passo, senão projetos salvos em v4
   não abrem.
5. **A sangria (`_bleed`, `panelBefore`/`panelAfter`) só pode ser removida do
   `PanelCanvas` depois** que nada mais o monta. O `PanelCanvas` ainda é usado
   pela galeria/preview (`TemplateCanvas`), que segue no modelo de painéis.

## 8. Verificação

- `flutter analyze` limpo.
- **218 testes verdes.** Os 7 arquivos não-panel-coupled do editor devem passar
  sem edição — é o critério de aceite real.
- No device: adicionar texto/imagem/forma, mover/pinçar/girar, undo/redo,
  adicionar e remover slide, pintar fundo de um slide, exportar (conferir N PNGs
  na ordem certa), reabrir o projeto salvo.
- Conferir que um projeto v3 antigo abre migrado e volta a salvar como v4.

---

## 9. Resultado

O plano foi seguido de ponta a ponta. As cinco armadilhas de §7 foram todas
tratadas; o que divergiu:

| Ponto do plano | Como ficou |
|---|---|
| §1 Estado | Como planejado. `_focusedPanelId` e `_panelKeys` morreram; sobram só comentários explicando por quê (`template_screen.dart:125`, `:508`). `Document _doc` + `_Snapshot` no histórico. |
| §5 Canvas | Um `CanvasView` sob a superfície de zoom, como planejado. |
| §6 Export | `capturePngSlices(_canvasKey, _doc, …)` em `_capturePanels()` (`template_screen.dart:1425`) — o nome do método ficou, o conteúdo é fatiamento. |
| §7.4 `projects_screen` | Feito: `loadAsDocument` em `projects_screen.dart:73` e `:207`. |
| §7.5 Sangria | Removida **inteira** no mesmo arco, não depois — `_bleed`/`panelBefore`/`panelAfter` não existem mais em `lib/`. `PanelCanvas` segue vivo, mas só para galeria/preview via `TemplateCanvas`. |
| **`LayersSheet` (não previsto)** | Não foi convertida. O editor sintetiza um `Panel` efêmero do slide em foco a cada rebuild e alimenta a sheet (`template_screen.dart:1356`). É o único ponto onde o vocabulário de painel sobrevive de forma executável. |
| Tamanho do alvo | 2034 → 2256 linhas. |

**Dívida deixada:** o adaptador `Panel` da `LayersSheet` acima. Converter a
sheet para falar `Document`/slide elimina a última construção de `Panel` no
editor.

### Estado da suíte

**`flutter test --concurrency=1` → 243/243 verdes; `flutter analyze` limpo.**

Chegou-se aqui consertando duas falhas que **não vinham desta conversão**.
Registro do que eram, porque a causa foi contra-intuitiva:

Em `ac4e19f` a suíte estava em 241 passam / 2 falham, ambas em
`test/selection_gesture_surface_test.dart`. Não eram regressão: foram
commitadas já vermelhas em `1ff8a76 improve extrapolate` e nunca passaram —
verificado rodando o arquivo num worktree em `1ff8a76`, onde falham com os
mesmos valores exatos de 68 commits depois. Passaram despercebidas porque
`flutter test | tail` devolve o exit code do `tail`, não do teste.

- `pinch anywhere resizes the selected element` — espera `1.5`, obtém `1.875`.
- `two-finger twist rotates the selected element` — espera escala `1.0`
  (o twist não muda tamanho), obtém `1.25`. A asserção de rotação passa.

Ambas erram pelo **mesmo fator 1.25** — fator constante, não erro de razão. E
1.25 é exatamente o que o movimento de aceitação do recognizer produz no
cenário do teste (span 200 → 250).

Causa mecânica: `_SelectionGestureSurface._onScaleUpdate`
(`lib/src/rendering/template_canvas.dart:3150`) re-baseia `_baseScale` na
transição de 1 → 2 dedos, que acontece **antes** do movimento de aceitação. O
comentário do teste (`selection_gesture_surface_test.dart:121-123`) assume o
re-base **no momento da aceitação**. Essa divergência existe desde o dia em que
o teste foi escrito — daí ele nunca ter passado. O movimento de slop entra como
pinça de verdade e o 1.25 sobra na escala final.

**Resolvido: o errado é o teste.** Medido com um `GestureDetector` cru (zero
código do app), a mesma sequência de gestos faz o Flutter reportar
`scale=1.2500` e depois `scale=1.8750` — exatamente os valores que o teste
acusa como falha. O `ScaleGestureRecognizer` **não** re-baseia na aceitação:
captura `_initialSpan` nos *pointer-downs* (span 200) e nunca mais. O sinal
decisivo é que o `onScaleStart` de 2 dedos chega com `focal=(275,300)` — ponto
médio já *depois* do movimento de aceitação — e ainda assim o primeiro update
vem `1.25`, ou seja `250/200`.

Consequência: `_SelectionGestureSurface` está correto, só repassa
`_baseScale * d.scale`. **Nada a corrigir em `template_canvas.dart`.** O
comportamento de produto também está certo — os dedos vão de 200 a 375 px de
distância e o elemento cresce 1.875×; o "movimento de aceitação" não é
artefato, é o usuário afastando os dedos.

Correções aplicadas nos testes:

- `pinch anywhere resizes…` — o esperado virou `1.875` (375/200) e o comentário
  passou a descrever o contrato real do recognizer.
- `two-finger twist rotates…` — o gesto foi reconstruído como um giro de 90° em
  torno de (300,300) que **termina no mesmo span de 200** em que começou. Agora
  o `closeTo(1.0, 0.05)` afirma de fato "girar não redimensiona", em vez de ser
  um número calibrado para o que o gesto por acaso fazia.

### O bug que o teste corrigido revelou

Com o twist virando um giro puro, ele passou a falhar num ponto **novo**: a
escala terminava em `0.7071` (o span intermediário de 141,4/200) em vez de
voltar a `1.0`. Causa: o guard `if (d.pointerCount >= 2 && d.scale != 1.0)`.

`d.scale` é uma razão **absoluta** contra o span do touch-down, não um delta —
então pular um update não é "não fazer nada", é deixar o elemento num valor
obsoleto de um frame anterior. Um gesto que volta ao span inicial reporta
exatamente `1.0`, cai no guard, e o tamanho fica preso no do meio do caminho.

O guard tinha, ainda assim, um propósito legítimo: num *pan* de dois dedos o
span não muda, `d.scale` é `1.0` todo frame, e chamar `onScaleChange` ali seria
um `setState` redundante por frame. A correção preserva os dois lados — guardar
pelo **valor resultante** em vez de por `d.scale != 1.0`:

```dart
if (d.pointerCount >= 2) {
  final next = (_baseScale * d.scale).clamp(_kMinSlotScale, _kMaxSlotScale);
  if (next != widget.currentScale) widget.onScaleChange?.call(id, next);
}
```

O pan de dois dedos segue sem escrever nada (`next == currentScale`), e o
retorno ao span inicial volta a aplicar. `d.rotation != 0` tinha o mesmo
defeito e recebeu o mesmo tratamento. Aplicado nos **dois** `_onScaleUpdate` —
`_SlotGestureDetector` (pinça sobre o elemento) e `_SelectionGestureSurface`
(pinça em qualquer lugar) — que já eram cópias um do outro por contrato.

Origem: o guard veio de `1ff8a76`, o mesmo commit dos testes vermelhos. Nunca
tinha sido exercitado.

**Pendente fora deste passo:** a fase 5 do RFC (o `collageweb` autorar v4). O
formato de fio ainda é v3 — `kSupportedSchemaVersion = 3` no app e
`CURRENT_SCHEMA_VERSION = 3` no web. Templates publicados chegam em painéis e
o editor os dobra no modelo contínuo na entrada, via
`_documentFrom` → `migrateToV4` (`template_screen.dart:1115`).
