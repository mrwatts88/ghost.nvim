# Records assets/demo.gif. From the repo root:  vhs assets/demo.tape
# Uses your own Neovim config, so ghost.nvim must be installed and its backend
# logged in. Answers are real requests, so they vary a little between runs.

Output assets/demo.gif

Set Shell "zsh"
Set FontFamily "Hack Nerd Font Mono"
Set FontSize 20
Set Width 1300
Set Height 720
Set Padding 16
Set TypingSpeed 40ms

# A fresh throwaway project each run, so nothing is cached yet. Neovim runs
# under assets/vhs.terminfo, which spells truecolor as `38;2;r;g;b`; on its
# own it picks the colon form, which vhs's terminal misreads as a green tint.
Hide
Type `repo=$PWD && cd "$(mktemp -d)" && tic -x -o ti "$repo/assets/vhs.terminfo" && git init -q && mkdir src && printf 'fn main() {\n    let word = "ghost";\n}\n' > src/main.rs && TERMINFO=$PWD/ti TERM=xterm-vhs COLORTERM=truecolor nvim src/main.rs`
Enter
Sleep 3s
Show

Sleep 1s

# A code question: the answer is the code to type by hand.
Type "2Go"
Type "// ? reverse the word and print it"
Escape
Sleep 700ms
Space
Type "ii"
Wait+Screen@60s /rev\(\)/
Sleep 3s

# An editor question: answered with this setup's own tmux bindings.
Type "Go"
Type "// ? split tmux right"
Escape
Sleep 700ms
Space
Type "ii"
Wait+Screen@60s /C-a/
Sleep 5s
