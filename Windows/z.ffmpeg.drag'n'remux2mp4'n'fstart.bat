@echo off
IF "%~1"=="" exit
set ffmpeg="C:\Program Files\MeGUI\tools\ffmpeg\ffmpeg.exe"

set hour=%time:~,2%
if "%time:~,1%"==" " set hour=0%time:~1,1%
set output=%date:~0,4%%date:~5,2%%date:~8,2%%hour%%time:~3,2%%time:~6,2%

%ffmpeg% -i "%~dpnx1" -map 0 -movflags faststart -vcodec copy -acodec copy -scodec copy "%~dpn1.%output%.mp4"
