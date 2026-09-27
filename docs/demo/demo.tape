# Recording of docs/images/demo.gif and the screenshots next to it.
# Run via docs/demo/record.zsh (it builds the demo project and sets DEMO_DIR / REPO).
Output docs/images/demo.gif

Require fzf
Set Shell zsh
Set FontSize 15
Set Width 1440
Set Height 760
Set Padding 16
Set Theme "Catppuccin Mocha"
Set TypingSpeed 60ms
Set Framerate 20

Hide
Type `export PATH="$REPO:$PATH"; cd "$DEMO_DIR"; rm -rf PDF .nb2cleanpdf; PROMPT='%F{blue}~/my-project%f %# '; RPROMPT=''; clear`
Enter
Sleep 1s
Show

Sleep 500ms
Type "nb2cleanpdf"
Sleep 400ms
Enter
Sleep 2.5s

# fzf picker: walk the list (preview follows), unselect the draft
Down
Sleep 900ms
Down
Sleep 1.2s
Down
Sleep 700ms
Down
Sleep 700ms
Tab
Sleep 1.2s
Up
Sleep 1.5s
Screenshot docs/images/picker.png
Sleep 500ms
Enter
Sleep 1.5s
Type "y"
Sleep 300ms
Enter

# live progress line of the first notebook
Sleep 2.2s
Screenshot docs/images/run.png

# (vhs Wait only sees the first screenful, so sleep through the run)
Sleep 22s
Sleep 3s
Screenshot docs/images/summary.png
Sleep 1s
