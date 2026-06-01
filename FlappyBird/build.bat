@echo off
setlocal
for /f "usebackq tokens=*" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
  set InstallDir=%%i
)

if exist "%InstallDir%\VC\Auxiliary\Build\vcvars32.bat" (
  call "%InstallDir%\VC\Auxiliary\Build\vcvars32.bat"
  msbuild FlappyBird.App\FlappyBird.App.vcxproj /p:Configuration=Release /p:Platform=Win32
) else (
  echo Could not find vcvars32.bat
)
