# AGENTS.md

Guidance for coding agents working in `pawtocomplete.nvim`.

## Project Overview

`pawtocomplete.nvim` is a Neovim (`>= 0.12.0`) LSP completion popup and signature-help plugin written in Lua with a C++17 native Lua C module (`paw` compiled to `build/libpaw.so`).

- **Lua layer (`lua/pawtocomplete/`)**: Neovim autocommands, keymaps, debouncing, async LSP requests (`textDocument/completion`, `completionItem/resolve`, `textDocument/signatureHelp`), floating windows, ghost-text extmarks, and snippet/text-edit application.
- **C++ core (`src/`)**: Lua 5.1 C API module providing an LFU cache of completion items, subsequence filtering, weighted edit-distance scoring and sorting, string/table helpers, menu line formatting, and a stateful `Cat` mood emoji tracker.

## Build, Test, and Formatting Commands

- **Build C++ shared library (`build/libpaw.so`)**:
  ```bash
  make
  ```
  Runs `cmake -B build -DCMAKE_BUILD_TYPE=Release && make -C build`. CMake (`>= 3.14`) fetches Lua `v5.1` headers and Abseil C++ (`20250512.1`) via `FetchContent`.
- **Clean build artifacts**:
  ```bash
  make clean
  ```
- **Run full test suite**:
  ```bash
  make test
  ```
  Runs headless Neovim with `tests/init.lua` and `plenary.busted`. If `PLENARY_DIR` (default `/tmp/plenary.nvim`) does not exist, `tests/init.lua` clones `nvim-lua/plenary.nvim` into it.
- **Run a single test file**:
  ```bash
  nvim --headless --noplugin -u tests/init.lua -c "PlenaryBustedFile tests/pawtocomplete/<spec>.lua"
  ```
- **Always run `make` before `make test` after editing `src/`**: `lua/pawtocomplete/paw.lua` loads `build/libpaw.so` directly from `build/` via `package.cpath`.
- **C++ formatting**: Follow `.clang-format` (Google style, 2-space indent, `PointerAlignment: Left`). Compile with `-Wall -Wextra` clean.

## Repository Structure

### C++ Core (`src/`)

- `src/lfu.h`: Header-only `LFU<T, U, F, SIZE>` cache backed by `absl::flat_hash_map` and `std::list`. Note: `LFU::get(key)` default-inserts an entry if `key` is absent; check `has_value(key)` first if insertion is unwanted.
- `src/paw.h`: LSP enums (`CompletionItemKind`, `CompletionTriggerKind`), structs (`Position`, `Range`, `TextEdit`, `CompletionItem`, `EditDistanceOption`, `CompletionParam`), `CacheKey` (`{bufnr, line, col}`), `CatState`/`Cat`, and `Context` (`DEFAULT_CACHE_SIZE = 32768`).
- `src/paw.cc`: Holds `static Context context;` singleton and exports `luaopen_paw`:
  - Cache & ranking: `insert_items`, `get_completion_items`, `has_cache`, `clear_completion_items`
  - Text & LSP helpers: `trim_long_text`, `is_whitespace`, `find_last_word_index`, `find_last_trigger_index`, `get_completion_start`, `table_get`, `find_trigger_context`
  - UI formatting & cat state: `format_completion_item`, `get_stars`, `interact`, `cat_emoji`

### Lua Modules (`lua/pawtocomplete/`)

- `init.lua`: Public entrypoint `setup(opts)`. Checks Neovim `>= 0.12.0`, merges user options via `config.merge_option(opts)`, then calls `completion.setup()` and `signature.setup()`.
- `config.lua`: Default configuration (`completion`, `signature`), `merge_option(opt)`, and `get_config()`.
- `paw.lua`: Appends `../../build/lib?.so` (relative to itself) to `package.cpath` and returns `require('paw')`.
- `completion.lua`: Triggers completion on `TextChangedI` and `<C-Space>`, cancels stale requests (`context.request_ids`), clears cache on trigger and `BufWritePost`/`InsertLeavePre`, shows overlay ghost text (`pawtocomplete.completion` namespace), lazily resolves `completionItem/resolve`, and exports `apply_text_edit(item)` (supporting `TextEdit` / `InsertReplaceEdit` via `vim.lsp.util.apply_text_edits(..., 'utf-8')` and LSP snippets `insertTextFormat == 2` via `vim.snippet.expand`).
- `completion_menu.lua`: Renders the floating completion list (`PopupMenu` filetype, `PawItemKind*` highlight groups, `SYMBOLS` Nerd Font icon table) and attached preview window (cat mood emoji, index/total, star rating, cost, and markdown documentation). Sets buffer-local insert-mode `expr` keymaps (`<C-p>`, `<C-n>`, `<CR>`, `<C-e>` by default) and `PopupMenu` augroup `InsertLeave` cleanup.
- `signature.lua`: Triggers debounced `textDocument/signatureHelp` requests on `CursorMovedI` when the character before the cursor matches `signatureHelpProvider.triggerCharacters`, renders markdown via `vim.lsp.util.stylize_markdown`, highlights active parameters (`LspSignatureActiveParameter`), and positions the floating window above or below the cursor.
- `util.lua`: Shared helpers: `floating_dimensions`, `open_action_window`, `close_action_window`, `debounce`, and `throttle` (`vim.defer_fn`).

### Tests (`tests/`)

- `tests/init.lua`: Plenary test harness.
- `tests/pawtocomplete/completion_spec.lua`: `completion.apply_text_edit` and snippet expansion tests.
- `tests/pawtocomplete/config_spec.lua`: Default config and `merge_option` tests.
- `tests/pawtocomplete/paw_spec.lua`: Unit tests and timing benchmarks for the `paw` C++ module.
- `tests/pawtocomplete/ui_spec.lua`: `completion_menu` open/close, navigation, empty items, and documentation tests.
- `tests/pawtocomplete/util_spec.lua`: `floating_dimensions`, `debounce`, and `throttle` tests.

## Key Conventions and Subtle Behaviors

- **Lua 5.1 C API ABI**: `CMakeLists.txt` compiles `src/paw.cc` against Lua `v5.1` headers without linking a Lua runtime library (`libpaw.so` resolves symbols from Neovim's LuaJIT runtime at load time). Stick to Lua 5.1 C API calls (`lua_objlen`, `luaL_checkint`, `luaL_optinteger`, etc.).
- **Index conventions across the Lua/C++ boundary**:
  - `find_last_word_index`, `find_last_trigger_index`, `get_completion_start`, and `find_trigger_context` work on **0-indexed** offsets in `line_to_cursor` (word characters are `isalnum(c) || c == '_' || c == '-'`).
  - `insert_items(items, client_id, bufnr, line, col)` and `get_completion_items(bufnr, line, col, start, option)` take **1-indexed** `line`, `col`, and `start` from Lua (`completion.lua` passes `pos[1]`, `pos[2]`, `start + 1`). When an item lacks `textEdit`, `get_completion_items` synthesizes a **0-indexed** LSP `TextEdit` range `{line - 1, start - 1}` to `{line - 1, col}`.
  - `completion.lua`'s `parse_completion_edit` converts 0-indexed LSP `range.start.line` via `+ 1` for Neovim cursor rows.
- **C++ <-> Lua item field mapping**: `push_completion_item` converts C++ snake_case fields to LSP camelCase (`clientId`, `sortText`, `filterText`, `insertText`, `insertTextFormat`, `textEdit`, `newText`). `documentation` is not parsed or cached in C++; it lives only on the Lua item tables (populated via `completionItem/resolve`).
- **Config reference semantics**: `completion.lua` and `signature.lua` capture `config.get_config()` at module load time, while `config.merge_option(opt)` reassigns the local `config` variable in `config.lua` using `vim.tbl_deep_extend`. Always call `config.merge_option` before requiring `completion` or `signature` (as `init.lua` does), or mutate carefully if changing config behavior.
- **Intentional key spelling**: `substitude_cost` (spelled with `d`) is used across `config.lua`, `completion.lua`, `paw.h`, `paw.cc`, `README.md`, and `tests/pawtocomplete/paw_spec.lua`. Keep it consistent across all layers if referenced or modified.
- **Cost normalization & sorting**: `lua_get_completion_items` min-max scales item `cost` into `[0, 5]` (`MAX_STARS`) across cached items at that key, filters out non-subsequences (`!item.is_subseq`), and sorts by `(insertTextFormat desc, cost asc, sortText asc, label asc)`. Note that `EditDistanceOption.max_cost` is parsed in `src/paw.cc` but currently unused for filtering.
- **Singleton C++ cache in tests**: `src/paw.cc` holds `static Context context;`; call `paw.clear_completion_items()` in tests that share `(bufnr, line, col)` keys to avoid cross-test cache pollution.
- **Lua style**: 2-space indentation, `local api = vim.api` / `lsp = vim.lsp` / `fn = vim.fn` module headers, `local M = {}` exports. Use `vim.schedule` when modifying windows/buffers from `expr` keymaps or async callbacks (`completion_menu.lua`).
