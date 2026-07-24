Option Explicit

Dim fso, botDir, runScript

Set fso = CreateObject("Scripting.FileSystemObject")
botDir = fso.GetParentFolderName(WScript.ScriptFullName)
runScript = fso.BuildPath(botDir, "run_hidden.vbs")

CreateObject("WScript.Shell").Run "wscript.exe //B """ & runScript & """", 0, False
