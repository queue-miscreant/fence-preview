fence-preview
=============

A plugin for previewing images from nvim.
Somewhat of a reimplementation of [vim-graphical-preview](https://github.com/bytesnake/vim-graphical-preview),
which refused to compile on my Linux box.

A sister project to [nvim-image-extmarks](https://github.com/queue-miscreant/nvim-image-extmarks),
which it depends upon.

Neovim 0.10 note: drawing images at virt_lines extmarks requires text_height.
Use prior virt_lines implementation by default for those versions.


Requirements
------------

- ImageMagick
- LaTeX (optional)
- gnuplot (optional)
- Plugins
    - [nvim-image-extmarks](https://github.com/queue-miscreant/nvim-image-extmarks)


Installation
------------

### Vundle

<!--
Place the following in `~/.config/nvim/init.vim`:
```vim
Plugin '...', { 'do': ':UpdateRemotePlugins' }
```
Make sure the file is sourced and run `:PluginInstall`.
-->


Commands
--------

Plugin commands


Functions
---------

Exposed functions


Keys
----

Plugin keybinds


Configuration
-------------

Global variables


Highlights
----------

Plugin highlights


TODOs
-----

- Refactor extmark manipulations into its own file
- Cache files in persistent directory between sessions
- Documentation
- Only run pipeline when content changes
- Add ability to halt running pipelines
- Better splits
    - Preambles for fence content (TeX for math so that syntax works properly, Python imports(?))
