#!/bin/bash
#written by @rzcat :)

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
#tunectl=film #目前闲置
MuxLang=eng
dar=16:9

input="$1/$2"
outputdir=/home/rzcat/x265/output
output=$(basename $1)
echo
echo Input: 
for f in $input; do echo "        $f"; done

AudioNum=$(ffmpeg-10bit -f concat -safe 0 -i <(for f in $input; do echo "file '$f'"; done) 2>&1 | grep "Audio" | wc -l)
SubNum=$(ffmpeg-10bit -f concat -safe 0 -i <(for f in $input; do echo "file '$f'"; done) 2>&1 | grep "Subtitle" | wc -l)
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
for EveryFile in $input
do
	if [ $ChapterIndex -lt 10 ]; then
		ChapterIndexStr=0$ChapterIndex
	else
		ChapterIndexStr=$ChapterIndex
	fi
	echo CHAPTER${ChapterIndexStr}NAME=$(basename "$EveryFile")>>"$outputdir/$output.chapter.txt"
	Duration=$(ffmpeg-10bit -i "$EveryFile" 2>&1 | grep "Duration"| cut -d ' ' -f 4 | sed s/,// )
	TimePointer=$(echo $TimePointer+$(echo $Duration | awk '{ split($0, A, ":"); print (3600*A[1] + 60*A[2] + A[3])*100 }') | bc)
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
	if [ -f "$outputdir/$output.tmp.mp4" ]; then
		rm -f "$outputdir/$output.tmp.mp4"
	fi
	if [ ! -f "$outputdir/$output.done.mp4" ]; then
		ffmpeg-10bit -hide_banner \
			-f concat -safe 0 -i <(for f in $input; do echo "file '$f'"; done)  \
			-map 0:v:0 \
			-map_chapters 0 \
			-aspect $dar \
			-vcodec libx265 \
			-pix_fmt yuv420p10le \
			-preset $speedctl \
			-crf $videoencq \
			-an \
			-sn \
			"$outputdir/$output.tmp.mp4"&&mv "$outputdir/$output.tmp.mp4" "$outputdir/$output.done.mp4"
	fi
	
	for ((mapindex=0; mapindex<$AudioNum; ++mapindex))
	do
		if [ -f "$outputdir/$output.tmp.m4a" ]; then
			rm -f "$outputdir/$output.tmp.m4a"
		fi
		if [ ! -f "$outputdir/$output.a$mapindex.m4a" ]; then
			ffmpeg-10bit -hide_banner \
				-v quiet \
				-f concat -safe 0 -i <(for f in $input; do echo "file '$f'"; done) \
				-vn -sn -dn \
				-map 0:a:$mapindex \
				-acodec pcm_f32le \
				-f wav pipe:|neroAacEnc \
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
			ffmpeg-10bit -hide_banner \
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
				'(' $outputdir/$output.done.mp4 ')' \
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
				rm -f "$outputdir/$output.done.mp4"
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
				'(' $outputdir/$output.done.mp4 ')' \
				$cmd_mux_audio \
				--title "" \
				$cmd_mux_tail&&mv "$outputdir/$output.tail.mkv" "$outputdir/$output.$tail.mkv"
			if [ -f "$outputdir/$output.$tail.mkv" ]; then
				rm -f "$outputdir/$output.done.mp4"
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
