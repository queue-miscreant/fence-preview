fence-preview
=============

A plugin for previewing images from nvim.
Somewhat of a reimplementation of [vim-graphical-preview](https://github.com/bytesnake/vim-graphical-preview),
which refused to compile on my Linux box.

A sister project to [nvim-image-extmarks](https://github.com/queue-miscreant/nvim-image-extmarks),
which it depends upon.


Requirements
------------

- ImageMagick
- LaTeX (optional)
- Python libraries:
    - pynvim
    - wand (Python ImageMagick wrapper)
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

- Some pipelines need to not be automatic (Python) 
- Better splits
    - Preambles for fence content (TeX for math so that syntax works properly, Python imports(?))
- Default LaTeX display is not eye-searing
    - Simple: white text on black
    - Difficult: configurable, white text on configurable
        - use `background` option by default
