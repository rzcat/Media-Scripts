#!/bin/bash

SecToPlayTime () {
	hh=$(echo $1/360000|bc)
	mm=$(echo "($1/100-$hh*3600)/60"|bc)
	ss=$(echo "($1/100-$hh*3600)%60"|bc)
	cc=$(echo $1%100|bc)
	if [ $hh -lt 10 ]; then
		hh=0$hh
	fi
	if [ $mm -lt 10 ]; then
		mm=0$mm
	fi
	if [ $ss -lt 10 ]; then
		ss=0$ss
	fi
	if [ $cc -lt 10 ]; then
		cc=0${cc}0
	else
		cc=${cc}0
	fi
	printf "$hh:$mm:$ss.$cc"
}

videoencq=21.7
audioencq=0.2
speedctl=slower
#tunectl=film #not using
MuxLang=eng
dar=16:9

input="$1/$2"
outputdir=/path/to/outputdir
output=$(basename $1)
echo
echo Input: 
for f in $input; do echo "        $f"; done

AudioNum=$(ffmpeg -f concat -safe 0 -i <(for f in $input; do echo "file '$f'"; done) 2>&1 | grep "Audio" | wc -l)
SubNum=$(ffmpeg -f concat -safe 0 -i <(for f in $input; do echo "file '$f'"; done) 2>&1 | grep "Subtitle" | wc -l)
if [ $SubNum -gt 0 ]; then
	tail=\(x265cmb_${AudioNum}Aac_${SubNum}Sub.${videoencq}_${audioencq}.${speedctl}\)
else
	tail=\(x265cmb_${AudioNum}Aac.${videoencq}_${audioencq}.${speedctl}\)
fi

echo Output:
echo "        ${outputdir}/${output}.$tail.mkv"
echo

if [ -f "$outputdir/$output.chapter.txt" ]; then
	rm -f "$outputdir/$output.chapter.txt"
fi
TimePointer=0
ChapterIndex=1
echo CHAPTER01=00:00:00.000>"$outputdir/$output.chapter.txt"
#echo CHAPTER!ChapterIndexStr!=00:00:00.000>"$outputdir/$output.chapter.txt" 
for EveryFile in $input
do
	if [ $ChapterIndex -lt 10 ]; then
		ChapterIndexStr=0$ChapterIndex
	else
		ChapterIndexStr=$ChapterIndex
	fi
	echo CHAPTER${ChapterIndexStr}NAME=$(basename "$EveryFile")>>"$outputdir/$output.chapter.txt"
	#echo "This is $EveryFile"
	Duration=$(ffmpeg -i "$EveryFile" 2>&1 | grep "Duration"| cut -d ' ' -f 4 | sed s/,// )
	#echo $Duration
	#echo $(echo $Duration | awk '{ split($0, A, ":"); print (3600*A[1] + 60*A[2] + A[3])*100 }')
	TimePointer=$(echo $TimePointer+$(echo $Duration | awk '{ split($0, A, ":"); print (3600*A[1] + 60*A[2] + A[3])*100 }') | bc)
	#echo $TimePointer
	#SecToPlayTime $TimePointer
	ChapterIndex=$(echo $ChapterIndex+1|bc)
	if [ $ChapterIndex -lt 10 ]; then
		ChapterIndexStr=0$ChapterIndex
	else
		ChapterIndexStr=$ChapterIndex
	fi
	echo CHAPTER${ChapterIndexStr}=$(SecToPlayTime $TimePointer)>>"$outputdir/$output.chapter.txt"
done
ChapterIndex=$(wc -l <(for f in ""$input""; do echo "a"; done) | awk '{ split($0, A, " "); print A[1] }')
ChapterIndex=$(echo $ChapterIndex+1|bc)
if [ $ChapterIndex -lt 10 ]; then
	ChapterIndexStr=0$ChapterIndex
else
	ChapterIndexStr=$ChapterIndex
fi
echo CHAPTER${ChapterIndexStr}NAME=End>>"$outputdir/$output.chapter.txt"
cmd_mux_tail='--chapter-language '$MuxLang' --chapters '"$outputdir/$output.chapter.txt"' --track-order 0:0'

if [ -f "$outputdir/$output.$tail.mkv" ]; then
	echo "Warning: Output File Already Exists, nothing touched."
else
	Input_File_List=$(for f in $input; do echo "-i $f "; done)
	Input_File_Num=$((for f in $input; do echo 1; done) | wc -l)
	Input_File_Video_Map_List_setPTS=$(for ((Input_File_List_Index=0; Input_File_List_Index<$Input_File_Num; ++Input_File_List_Index)); do printf '['$Input_File_List_Index':v:0]setpts=PTS-STARTPTS,mpdecimate[v'$Input_File_List_Index'];['$Input_File_List_Index':a:0]asetpts=PTS-STARTPTS[a'$Input_File_List_Index'];'; done)
	Input_File_Map_List_Tail=$(for ((Input_File_List_Index=0; Input_File_List_Index<$Input_File_Num; ++Input_File_List_Index)); do printf '[v'$Input_File_List_Index'][a'$Input_File_List_Index']'; done)
	
	if [ -f "$outputdir/$output.tmp.mkv" ]; then
		rm -f "$outputdir/$output.tmp.mkv"
	fi
	if [ ! -f "$outputdir/$output.done.mkv" ]; then #20171021 use filter_complex to concatenate instead of -f concat
		ffmpeg -hide_banner \
			$Input_File_List \
			-filter_complex "$Input_File_Video_Map_List_setPTS $Input_File_Map_List_Tail concat=n=$Input_File_Num:v=1:a=1 [out]" \
			-map "[out]" \
			-vsync vfr \
			-aspect $dar \
			-vcodec libx265 \
			-pix_fmt yuv420p10le \
			-preset $speedctl \
			-crf $videoencq \
			-acodec pcm_s16le \
			-f tee "[select=v]$outputdir/$output.tmp.mkv"&&mv "$outputdir/$output.tmp.mkv" "$outputdir/$output.done.mkv"
	fi
	
	for ((mapindex=0; mapindex<$AudioNum; ++mapindex))
	do
		Input_File_Audio_Map_List_setPTS=$(for ((Input_File_List_Index=0; Input_File_List_Index<$Input_File_Num; ++Input_File_List_Index)); do printf '['$Input_File_List_Index':v:0]crop=2:2,setpts=PTS-STARTPTS,mpdecimate[v'$Input_File_List_Index'];['$Input_File_List_Index':a:$mapindex]asetpts=PTS-STARTPTS[a'$Input_File_List_Index'];'; done)

		if [ -f "$outputdir/$output.tmp.m4a" ]; then
			rm -f "$outputdir/$output.tmp.m4a"
		fi
		if [ ! -f "$outputdir/$output.a$mapindex.m4a" ]; then #20171021 use filter_complex to concatenate instead of -f concat
			ffmpeg -hide_banner \
				-v quiet \
				$Input_File_List \
				-filter_complex "$Input_File_Audio_Map_List_setPTS $Input_File_Map_List_Tail concat=n=$Input_File_Num:v=1:a=1 [out]" \
				-map "[out]" \
				-vcodec rawvideo \
				-acodec pcm_f32le \
				-f tee "[select=a:f=wav]pipe\:"|neroAacEnc \
				-ignorelength \
				-q $audioencq \
				-if - -of "$outputdir/$output.tmp.m4a"&&mv "$outputdir/$output.tmp.m4a" "$outputdir/$output.a$mapindex.m4a"
		fi
	done		
	cmd_mux_audio=$(for ((mapindex=0; mapindex<$AudioNum; ++mapindex)); do \
		printf ' --no-track-tags --no-chapters --language 0:'$MuxLang' ( '$outputdir'/'$output'.a'$mapindex'.m4a )'; done)
	cmd_mux_tail='--chapter-language '$MuxLang' --chapters '"$outputdir/$output.chapter.txt"' --track-order 0:0'$(for ((mapindex=0; mapindex<$AudioNum; ++mapindex)); do \
		printf ','$(($mapindex+1))':0'; done)
	if [ $SubNum -gt 0 ]; then
		if [ -f "$outputdir/$output.subtmp.mkv" ]; then
			rm -f "$outputdir/$output.subtmp.mkv"
		fi
		if [ ! -f "$outputdir/$output.sub.mkv" ]; then
			ffmpeg -hide_banner \
				-v quiet \
				-f concat -safe 0 -i <(for f in $input; do echo "file '$f'"; done) \
				-map 0 \
				-map_chapters -1 \
				-an -vn \
				-scodec copy \
				"$outputdir/$output.subtmp.mkv"&&mv "$outputdir/$output.subtmp.mkv" "$outputdir/$output.sub.mkv"
		fi
		if [ ! -f "$outputdir/$output.$tail.mkv" ]; then
			mkvmerge \
				--output "$outputdir/$output.tail.mkv" \
				--no-audio \
				--no-subtitles \
				--no-track-tags \
				--no-global-tags \
				--language 0:$MuxLang \
				--default-track 0:yes \
				--aspect-ratio 0:$dar \
				--track-name 0:"" \
				'(' $outputdir/$output.done.mkv ')' \
				$cmd_mux_audio \
				--no-chapters \
				--no-audio \
				--no-video \
				--no-track-tags \
				--no-global-tags \
				'(' $outputdir/$output.sub.mkv ')' \
				--title "" \
				$cmd_mux_tail&&mv "$outputdir/$output.tail.mkv" "$outputdir/$output.$tail.mkv"
			if [ -f "$outputdir/$output.$tail.mkv" ]; then
				rm -f "$outputdir/$output.done.mkv"
				rm -f "$outputdir/$output.sub.mkv"
				rm -f "$outputdir/$output.chapter.txt"
				for ((mapindex=0; mapindex<$AudioNum; ++mapindex))
				do
					rm -f "$outputdir/$output.a$mapindex.m4a"
				done
			fi
		fi
	else
		if [ ! -f "$outputdir/$output.$tail.mkv" ]; then
			mkvmerge \
				--output "$outputdir/$output.tail.mkv" \
				--no-audio \
				--no-subtitles \
				--no-track-tags \
				--no-global-tags \
				--language 0:$MuxLang \
				--default-track 0:yes \
				--aspect-ratio 0:$dar \
				--track-name 0:"" \
				'(' $outputdir/$output.done.mkv ')' \
				$cmd_mux_audio \
				--title "" \
				$cmd_mux_tail&&mv "$outputdir/$output.tail.mkv" "$outputdir/$output.$tail.mkv"
			if [ -f "$outputdir/$output.$tail.mkv" ]; then
				rm -f "$outputdir/$output.done.mkv"
				rm -f "$outputdir/$output.chapter.txt"
				for ((mapindex=0; mapindex<$AudioNum; ++mapindex))
				do
					rm -f "$outputdir/$output.a$mapindex.m4a"
				done
			fi
		fi
	fi
	if [ -f "$outputdir/$output.chapter.txt" ]; then
		rm -f "$outputdir/$output.chapter.txt"
	fi
fi
