# VHS tape for docs/demo.gif. See docs/demo.md for how to regenerate it.
# Run it from the repository root: vhs docs/demo.tape

Output docs/demo.gif

Set Shell "bash"
Set FontSize 14
Set Width 1200
Set Height 400
Set Padding 20
Set TypingSpeed 35ms
Set Theme "Catppuccin Mocha"

Hide
Type "source docs/demo-setup.sh && clear"
Enter
Sleep 1s
Show

Type "cat ~/accounts.json"
Sleep 300ms
Enter
Sleep 2s

Type "ccuse work -n demo"
Sleep 300ms
Enter
Sleep 2.5s

Type "# the status line of a work session at 96% of its 5h limit"
Enter
Type "statusline.sh < ~/session.json; echo"
Sleep 300ms
Enter
Sleep 3.5s

Type "ccswitch"
Sleep 300ms
Enter
Sleep 4s
