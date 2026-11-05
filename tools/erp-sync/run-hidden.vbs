' Starts the sync under 32-bit PowerShell with no window flashing on the screen.
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = """C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & here & "\erp-sync.ps1"""
WScript.Quit CreateObject("WScript.Shell").Run(cmd, 0, True)
