# Testes

Os testes ficam separados por linguagem. Rode tudo a partir da raiz do repositório.

| Pasta | Conteúdo | Como rodar |
| --- | --- | --- |
| `cpp/` | Testes do núcleo C++, ligados ao CMake pelas opções `TFS_BUILD_*_TESTS`. | `cmake -S . -B build -DTFS_BUILD_RARITY_TESTS=ON` (e outras opções) e depois `ctest --test-dir build` |
| `lua/` | Scripts do servidor e módulos do cliente com objetos simulados. | `luajit tests/lua/<nome>-tests.lua` |
| `python/` | Verificações de código, dados, workflows e do README. | `PYTHONPATH=tests/python python3 -m unittest discover -s tests/python -p "test_*.py"` |
| `php/` | Páginas do site. | `php tests/php/<nome>-tests.php` |
| `launcher/` | Launcher Windows e empacotamento do cliente (.NET e PowerShell). | `dotnet run --project tests/launcher/LauncherSafetyTests.csproj` |

Outros arquivos:

- `fixtures/`: dados de referência usados pelos testes.
- `cppcheck-baseline.json` e `lua-lint-baseline.json`: achados já conhecidos do cppcheck e do lint de Lua. O CI só falha com achados novos.

A lista completa das opções `TFS_BUILD_*` está no [CMakeLists.txt](../CMakeLists.txt). O [workflow de build](../.github/workflows/security-build.yml) mostra quais suítes rodam em cada verificação.
