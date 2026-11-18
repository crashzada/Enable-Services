# Enable-Services

Verifica os serviços do Windows pedidos em screenshare (`PcaSvc`, `SysMain`, `DPS`, `Bam`, `DusmSvc`, `DiagTrack` e `EventLog`) e, se você quiser, ativa os que estiverem desativados ou parados.

Na lista, **verde** significa ativo e **vermelho** significa desativado ou parado. O status aparece como `Running`, `Stopped`, `Disabled` ou `Not found`.

## Como usar

Abra o PowerShell como **administrador** e execute:

```powershell
irm https://raw.githubusercontent.com/crashzada/Enable-Services/main/Enable-Services.ps1 | iex
```
