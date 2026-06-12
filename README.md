# collageapp

App mobile do Collage Studio: baixa os templates (JSON) da API do editor
web e os renderiza em Flutter. O usuário preenche os slots de texto e
imagem e exporta a arte final em PNG.

Como rodar no device físico (túnel adb, ponte IPv4, dev server):
ver [`collageweb/DEVELOPMENT.md`](../collageweb/DEVELOPMENT.md).

Testes: `flutter test` (inclui goldens do renderer em `test/goldens/`).
