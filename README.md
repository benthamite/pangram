# `pangram`: AI content detection via Pangram API

## Overview

`pangram` provides an Emacs interface to the [Pangram Labs API (v3)](https://pangram.readthedocs.io/en/latest/api/rest.html) for detecting AI-generated content in text. Given a buffer or an active region, the package sends the text to Pangram's inference endpoint and visually highlights segments that the API classifies as AI-generated or AI-assisted, using distinct overlay faces. Human-written segments are left unmarked.

The core workflow is straightforward: invoke `M-x pangram-detect` to analyze text, then hover over highlighted segments to see classification details (label, confidence score, and AI assistance score) in the echo area. After analysis, a summary line shows the overall verdict and the percentage breakdown across AI-generated, AI-assisted, and human categories. When you are done reviewing, invoke `M-x pangram-clear` to remove the overlays.

The package recognizes three segment categories: **AI-generated** (highlighted with a red-tinted background), **AI-assisted** (highlighted with an amber-tinted background), and **Human** (not highlighted). Both faces adapt to light and dark backgrounds automatically.

## Installation

`pangram` requires Emacs 29.1 or later. All dependencies (`json`, `url`, `auth-source-pass`, `seq`) are built-in Emacs libraries.

Before using the package, you need:

1. A Pangram Labs API key (sign up at [pangram.com](https://pangram.com)).
2. The `pass` password manager with `auth-source-pass` configured in Emacs.
3. The environment variable `PERSONAL_EMAIL` set to the email associated with your Pangram account.

Store your API key in the pass store under `chrome/pangram.com/YOUR_EMAIL`, with the key in a field named `key`.

### package-vc (built-in since Emacs 30)

```emacs-lisp
(use-package pangram
  :vc (:url "https://github.com/benthamite/pangram"))
```

### Elpaca

```emacs-lisp
(use-package pangram
  :ensure (:host github :repo "benthamite/pangram"))
```

### straight.el

```emacs-lisp
(use-package pangram
  :straight (:host github :repo "benthamite/pangram"))
```

## Quick start

```emacs-lisp
(use-package pangram
  :ensure (pangram :host github :repo "benthamite/pangram")
  :commands (pangram-detect pangram-clear))

;; If your shell does not export PERSONAL_EMAIL to Emacs:
(setenv "PERSONAL_EMAIL" "user@example.com")
```

Select a region of text (or leave the whole buffer unselected) and run `M-x pangram-detect`. Hover over highlighted segments to inspect their classification, then run `M-x pangram-clear` when done.

## Documentation

For a comprehensive description of all user options, commands, and functions, see the [manual](https://stafforini.com/notes/pangram/).

## License

`pangram` is free software distributed under the terms of the [GNU General Public License, version 3](COPYING.txt) or later.
