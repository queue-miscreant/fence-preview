fence-preview
=============

![Video example](./fence_preview_example.mp4)

A plugin for previewing markdown content from nvim.
Somewhat of a reimplementation of [vim-graphical-preview](https://github.com/bytesnake/vim-graphical-preview),
which refused to compile on my Linux box.

A sister project to [nvim-image-extmarks](https://github.com/queue-miscreant/nvim-image-extmarks),
which it depends upon.

To use the plugin in a buffer, run the following in Lua

```lua
require("fence_preview").bind()
```

If you want this to run automatically in new buffers, set up an autocommand to do it for you:

```vim
autocmd FileType markdown lua require("fence_preview").bind()
```


Requirements
------------

- [nvim-image-extmarks](https://github.com/queue-miscreant/nvim-image-extmarks)
  - Depending on whether `virt_lines` is permitted (i.e., Neovim 0.10 or greater), images can appear differently.
- ImageMagick
- LaTeX (optional)
- gnuplot (optional)


Installation
------------

### Vundle

Place the following in `~/.config/nvim/init.vim`:
```vim
Plugin 'queue-miscreant/fence-preview'
```
Make sure the file is sourced and run `:PluginInstall`.


Details
-------

More details can be found in the included helpdoc.
Run `:help fence-preview` for more information.


TODOs
-----

- Manual foldmethod only for "inline" sixels
- Add ability to halt running pipelines
- Better splits
    - Preambles for fence content (TeX for math so that syntax works properly, Python imports(?))
- Curl remote images
