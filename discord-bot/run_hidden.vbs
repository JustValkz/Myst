Option Explicit

Dim shell, fso, botDir, nodePath, indexScript, wmi, procs, proc, cmdLine

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
botDir = fso.GetParentFolderName(WScript.ScriptFullName)
indexScript = fso.BuildPath(botDir, "src\index.js")

If BotIsRunning(indexScript) Then
    WScript.Quit 0
End If

nodePath = "C:\Program Files\nodejs\node.exe"
If Not fso.FileExists(nodePath) Then
    nodePath = "node.exe"
End If

shell.CurrentDirectory = botDir
shell.Run """" & nodePath & """ """ & indexScript & """", 0, False

Function BotIsRunning(scriptPath)
    On Error Resume Next
    BotIsRunning = False
    Set wmi = GetObject("winmgmts:\\.\root\cimv2")
    If Err.Number <> 0 Then Exit Function
    Set procs = wmi.ExecQuery("SELECT CommandLine FROM Win32_Process WHERE Name = 'node.exe'")
    For Each proc In procs
        cmdLine = LCase(proc.CommandLine & "")
        If InStr(cmdLine, LCase(scriptPath)) > 0 Then
            BotIsRunning = True
            Exit Function
        End If
    Next
End Function
