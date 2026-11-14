' Starts the KMR ERP bridge status icon with no window.
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run """C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & here & "\tray.ps1""", 0, False
