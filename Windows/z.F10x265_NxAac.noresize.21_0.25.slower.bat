@echo off
setlocal EnableDelayedExpansion
rem initially written by @rzcat at 2016.12.07 00:29

rem inputfilename,res,type,outputdir,lang
IF "%~1"=="" GOTO :error
IF "%~2"=="" GOTO :error
IF "%~3"=="" GOTO :error
IF "%~4"=="" GOTO :error
IF "%~5"=="" GOTO :error

if not exist "%~1" (
	echo The input path is not correct.
	goto error
)

set VideoEncQ=21.7
set AudioEncQ=0.25
set EncSpeed=slower
set MuxLang=%~5
set/a AudioTrackNum=0
set/a SubTrackNum=0
set tail=
set cmd_mux_audio=

if "%~2"=="4" (
	set width="960"
	set height="720"
	set dar=4:3
	set ffscale=960x720
	set dar2=4/3
)
if "%~2"=="16" (
	set width="1280"
	set height="720"
	set dar=16:9
	set ffscale=1280x720
	set dar2=16/9
)

if not exist ffmpeg.exe (
	set ffmpeg="C:\Program Files\MeGUI\tools\ffmpeg\ffmpeg-10bit.exe"
	if exist !ffmpeg! (
		copy !ffmpeg! ffmpeg.exe
	) else (
		echo ffmpeg path is not correct to copy from.
		goto error
	)
)
set ffmpeg=ffmpeg.exe
set neroaac="C:\Program Files\MeGUI\tools\eac3to\neroAacEnc.exe"
set mmg="C:\Program Files\MeGUI\tools\mkvmerge\mkvmerge.exe"

if "z%~x1"=="z.m3u" (
	set/a TimePointer=0
	set/a ChapterIndex=1
	set ChapterIndexStr=0!ChapterIndex!
	for /f "delims=" %%k in ("%~1") do (
		if not exist "%%k" (
			echo %%k
			echo The input list contains one file that does not exist.
			goto error
		)
	)
	if exist "%~4\%~n1_concat.txt" del/f/q "%~4\%~n1_concat.txt"
	if exist "%~4\%~n1_chapter.txt" del/f/q "%~4\%~n1_chapter.txt"
	>>"%~4\%~n1_chapter.txt" echo CHAPTER!ChapterIndexStr!=00:00:00.000
	for /f "delims=" %%k in (%~1) do (
		>>"%~4\%~n1_concat.txt" echo file '%%k'
		for /f "tokens=2-5 delims=,.: " %%a in ('ffmpeg -i "%%k" 2^>^&1^|findstr /r /c:"Duration"') do (
			>>"%~4\%~n1_chapter.txt" echo CHAPTER!ChapterIndexStr!NAME=%%~nk
			set/a ChapterIndex+=1
			if !ChapterIndex! lss 10 (set ChapterIndexStr=0!ChapterIndex!) else set ChapterIndexStr=!ChapterIndex!
			set/a TimePointer="!TimePointer!+(((%%a*60)+1%%b %% 100)*60+1%%c %% 100)*100+1%%d %% 100"
			set/a hh="(!TimePointer!/100)/3600"
			set/a mm="((!TimePointer!/100)-(!hh!*3600))/60"
			set/a ss="((!TimePointer!/100)-(!hh!*3600))%% 60"
			set/a cc="!TimePointer! %% 100"
			if !hh! lss 10 set hh=0!hh!
			if !mm! lss 10 set mm=0!mm!
			if !ss! lss 10 set ss=0!ss!
			if !cc! lss 10 set cc=0!cc!
			if !hh! equ 0 set hh=00
			if !mm! equ 0 set mm=00
			if !ss! equ 0 set ss=00
			if !cc! equ 0 set cc=00
			>>"%~4\%~n1_chapter.txt" echo CHAPTER!ChapterIndexStr!=!hh!:!mm!:!ss!.!cc!0
		)
	)
	>>"%~4\%~n1_chapter.txt" echo CHAPTER!ChapterIndexStr!NAME=End
	set ffinput=%~4\%~n1_concat.txt
	set ConCatFlag=-f concat -safe 0
	set cmd_mux_tail=--chapter-language %MuxLang% --chapters "%~4\%~n1_chapter.txt" --track-order 0:0
) else (
	set ffinput=%~dpnx1
	set ConCatFlag=
	set cmd_mux_tail=--track-order 0:0
)

for /f "tokens=2 delims=:(" %%i in ('%ffmpeg% %ConCatFlag% -i "%ffinput%" 2^>^&1^|findstr /r /c:"Stream #.*: Audio:"') do (
	set/a AudioTrackNum+=1
)
for /f "tokens=2 delims=:(" %%i in ('%ffmpeg% %ConCatFlag% -i "%ffinput%" 2^>^&1^|findstr /r /c:"Stream #.*: Subtitle:"') do (
	set/a SubTrackNum+=1
)

if %SubTrackNum% gtr 0 (
	set tail=(x265_%AudioTrackNum%Aac_%SubTrackNum%Sub.%VideoEncQ%_%AudioEncQ%.%EncSpeed%)
) else (
	set tail=(x265_%AudioTrackNum%Aac.%VideoEncQ%_%AudioEncQ%.%EncSpeed%)
)

if exist "%~4\%~n1.%tail%.mkv" (
	echo Output file detected, it's already there.
	goto done
)

if exist "%~4\%~n1_tmp.mp4" (
	echo Temp video file detect, deleting...
	del/f/q "%~4\%~n1_tmp.mp4"
)
if not exist "%~4\%~n1_done.mp4" (
	%ffmpeg% %ConCatFlag% ^
		-i "%ffinput%" ^
		-map 0:v:0 ^
		-map_chapters 0 ^
		-aspect %dar% ^
		-vcodec libx265 ^
		-pix_fmt yuv420p10le ^
		-preset %EncSpeed% ^
		-crf %VideoEncQ% ^
		-an ^
		-sn ^
		"%~4\%~n1_tmp.mp4"&&ren "%~4\%~n1_tmp.mp4" "%~n1_done.mp4"
) else (
	echo Video already encoded, skipping...
)

if not exist "%~4\%~n1_done.mp4" (
	echo Problem occurred when encoding video.
	goto error
)

for /l %%i in (1,1,%AudioTrackNum%) do (
	set/a mapindex=%%i-1
	if exist "%~4\%~n1_tmp%%i.m4a" (
		echo Temp audio file detect, deleting...
		del/f/q "%~4\%~n1_tmp%%i.m4a"
	)
	if not exist "%~4\%~n1_a%%i.m4a" (
		echo.Processing audio stream [%%i/%AudioTrackNum%] of input file, output to:
		echo %~4\%~n1_tmp%%i.m4a
		%ffmpeg% %ConCatFlag% ^
			-v quiet ^
			-i "%ffinput%" ^
			-vn -sn -dn ^
			-map 0:a:!mapindex! ^
			-acodec pcm_f32le ^
			-f wav pipe:|%neroaac% ^
			-ignorelength ^
			-q %AudioEncQ% ^
			-if - -of "%~4\%~n1_tmp%%i.m4a"&&ren "%~4\%~n1_tmp%%i.m4a" "%~n1_a%%i.m4a"
	) else (
		echo Audio already encoded, skipping...
	)
	if not exist "%~4\%~n1_a%%i.m4a" (
		echo Problem occurred when encoding audio.
		goto error
	)
	set cmd_mux_audio=!cmd_mux_audio! --no-track-tags --no-chapters --language 0:%MuxLang% "(" "%~4\%~n1_a%%i.m4a" ")"
	set cmd_mux_tail=!cmd_mux_tail!,%%i:0
)

if %SubTrackNum% gtr 0 (
	if exist "%~4\%~n1_subtmp.mkv" (
		echo Temp subtitle file detect, deleting...
		del/f/q "%~4\%~n1_subtmp.mkv"
	)
	if not exist "%~4\%~n1_sub.mkv" (
		%ffmpeg% %ConCatFlag% ^
			-i "%ffinput%" ^
			-map 0 ^
			-map_chapters -1 ^
			-an -vn ^
			-scodec copy ^
			"%~4\%~n1_subtmp.mkv"&&ren "%~4\%~n1_subtmp.mkv" "%~n1_sub.mkv"
	) else (
		echo Subtitle already extracted, skipping...
	)
	%mmg% ^
		--output "%~4\%~n1.tail.mkv" ^
		--no-audio ^
		--no-subtitles ^
		--no-track-tags ^
		--no-global-tags ^
		--language 0:%MuxLang% ^
		--default-track 0:yes ^
		--aspect-ratio 0:%dar% ^
		--track-name 0:"" ^
		"(" "%~4\%~n1_done.mp4" ")" ^
		%cmd_mux_audio% ^
		--no-chapters ^
		--no-audio ^
		--no-video ^
		--no-track-tags ^
		--no-global-tags ^
		"(" "%~4\%~n1_sub.mkv" ")" ^
		--title "" ^
		%cmd_mux_tail%&&ren "%~4\%~n1.tail.mkv" "%~n1.%tail%.mkv"
	if exist "%~4\%~n1.%tail%.mkv" (
		del/f/q "%~4\%~n1_done.mp4"
		del/f/q "%~4\%~n1_a*.m4a"
		del/f/q "%~4\%~n1_sub.mkv"
	) else (
		echo Problem occurred when muxxing files.
		goto error
	)
) else (
	%mmg% ^
		--output "%~4\%~n1.tail.mkv" ^
		--no-audio ^
		--no-subtitles ^
		--no-track-tags ^
		--no-global-tags ^
		--language 0:%MuxLang% ^
		--default-track 0:yes ^
		--aspect-ratio 0:%dar% ^
		--track-name 0:"" ^
		"(" "%~4\%~n1_done.mp4" ")" ^
		%cmd_mux_audio% ^
		--title "" ^
		%cmd_mux_tail%&&ren "%~4\%~n1.tail.mkv" "%~n1.%tail%.mkv"
	if exist "%~4\%~n1.%tail%.mkv" (
		del/f/q "%~4\%~n1_done.mp4"
		del/f/q "%~4\%~n1_a*.m4a"
	) else (
		echo Problem occurred when muxxing files.
		goto error
	)
)

if "z%~x1"=="z.m3u" (
	if exist "%~4\%~n1_concat.txt" del/f/q "%~4\%~n1_concat.txt"
	if exist "%~4\%~n1_chapter.txt" del/f/q "%~4\%~n1_chapter.txt"
)
goto done

:error
echo.
echo ERROR
echo.
pause
goto eof

:done
echo.
echo one job is done.
echo.

:eof
