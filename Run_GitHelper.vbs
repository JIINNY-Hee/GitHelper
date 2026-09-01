Option Explicit
Dim shell, fso, baseDir, ps1Path, cmd
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1Path = fso.BuildPath(baseDir, "GitHelper.ps1")
If Not fso.FileExists(ps1Path) Then
    MsgBox "GitHelper.ps1 was not found:" & vbCrLf & ps1Path, vbCritical, "GitHelper"
    WScript.Quit 1
End If
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & ps1Path & """"
shell.Run cmd, 0, False
