# PawToComplete.nvim 🐱

"autocomplete" with a "paw". A lightweight, high-performance Neovim completion and signature help plugin with a C++ core and a fun cat-themed interactive state.

## Features

- **Blazing Fast**: C++ core handles scoring, fuzzy matching, and LFU caching.
- **Visual Polish**:
    - Rounded borders for completion and signature windows.
    - Clean, modern layout with Nerd Font icons.
    - Ghost text (overlay) preview of completion items.
- **Smart Completion**:
    - Fuzzy matching using weighted edit distance.
    - Support for `completionItem/resolve` to fetch on-demand documentation.
    - Markdown rendering in the preview window.
- **Signature Help**:
    - Active parameter highlighting.
    - Markdown support for documentation.
- **Interactive Cat Theme**:
    - A digital cat 🐱 that reacts to your typing!
    - The cat's mood changes from happy to pouting or crying based on interaction frequency.
    - View your cat's status in the completion preview window with a star-based scoring system.

## Performance

Pawtocomplete uses a custom C++ module (`paw.cc`) to perform heavy lifting:
- **LFU Cache**: Efficiently caches LSP results.
- **Weighted Edit Distance**: Sophisticated scoring algorithm (alpha, beta, gamma weights).
- **Fast Lua/C Bridge**: Optimized data transfer between Neovim and the C++ core.

## Configuration

```lua
require('pawtocomplete').setup({
  completion = {
    delay = 200,             -- Debounce delay for completion triggering
    max_cost = 0.9,          -- Maximum cost for filtering items
    insert_cost = 1,         -- Weighted cost for insertions
    delete_cost = 1,         -- Weighted cost for deletions
    substitude_cost = 2,     -- Weighted cost for substitutions
  },
  signature = {
    delay = 100,             -- Debounce delay for signature help
    max_width = 120,
    max_height = 6,
  },
})
```

## Icons

Pawtocomplete uses Nerd Fonts for a premium look. Ensure you have a Nerd Font installed and enabled in your terminal.

## Emojis

The cat 🐱 goes through several states:
- Normal typing: 🐱 -> 😺 -> 😸 -> 😽
- Inactivity: 😿 -> 😾 -> 😼

Happy coding! 🐾
