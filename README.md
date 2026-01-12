# Execute vencord dev installer
- required: git, node.js, pnpm (installation will be checked and prompted on script execution)
```pwsh
(iwr -UseBasicParsing 'https://raw.githubusercontent.com/shadowpercifal/pwsh-simple/refs/heads/main/vencord-installer-v2.ps1').Content | iex
```
# Execute drover autoinstall (Direct mode)
- required: discord running (will be closed)
```pwsh
(iwr -UseBasicParsing 'https://raw.githubusercontent.com/shadowpercifal/pwsh-simple/refs/heads/main/drover-autoinstall.ps1').Content | iex
```
