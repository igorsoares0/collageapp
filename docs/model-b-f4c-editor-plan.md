# Modelo B — F4c: converter o editor para o canvas contínuo

Status: **plano pronto, não executado**. Pré-requisitos todos entregues e commitados.
Contexto: `docs/model-b-migration.md` (RFC).

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
