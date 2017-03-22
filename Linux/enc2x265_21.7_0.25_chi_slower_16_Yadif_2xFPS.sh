#/bin/bash
#written by @rzcat :)

function compress () {

	videoencq=21.7
	audioencq=0.2
	speedctl=slower
	#tunectl=film #目前x265闲置
	MuxLang=chi
	dar=16:9

	input="$1"
	outputdir=/home/rzcat/x265/output
	#注意上面这行末尾没有斜杠
	output=$(echo "$input"|sed -r 's/(.*)(\..*)/\1/g')
	output=$(basename "$output")

	if [ $(ffmpeg-10bit -i "$input" 2>&1 | grep "Subtitle" | wc -l) -gt 0 ]; then
		tail=\(x265_$(ffmpeg-10bit -i "$input" 2>&1 | grep "Audio" | wc -l)Aac_$(ffmpeg-10bit -i "$input" 2>&1 | grep "Subtitle" | wc -l)Sub.${videoencq}_${audioencq}.${speedctl}.2xFPS\)
	else
		tail=\(x265_$(ffmpeg-10bit -i "$input" 2>&1 | grep "Audio" | wc -l)Aac.${videoencq}_${audioencq}.${speedctl}.2xFPS\)
	fi

	echo
	echo Input: $input
	echo Output: $outputdir/$output.$tail.mkv
	echo

	if [ -f "$outputdir/$output.$tail.mkv" ]; then
		echo "Warning: Output File Already Exists, nothing touched."
	else
		if [ -f "$outputdir/$output.tmp.mp4" ]; then
			rm -f "$outputdir/$output.tmp.mp4"
		fi
		if [ ! -f "$outputdir/$output.done.mp4" ]; then
			ffmpeg-10bit -hide_banner \
				-i "$input" \
				-vf yadif=1:-1:0 \
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
		for ((mapindex=0; mapindex<$(ffmpeg-10bit -i "$input" 2>&1 | grep "Audio" | wc -l); ++mapindex))
		do
			if [ -f "$outputdir/$output.tmp.m4a" ]; then
				rm -f "$outputdir/$output.tmp.m4a"
			fi
			if [ ! -f "$outputdir/$output.a$mapindex.m4a" ]; then
				ffmpeg-10bit -hide_banner \
					-v quiet \
					-i "$input" \
					-vn -sn -dn \
					-map 0:a:$mapindex \
					-acodec pcm_f32le \
					-f wav pipe:|neroAacEnc \
					-ignorelength \
					-q $audioencq \
					-if - -of "$outputdir/$output.tmp.m4a"&&mv "$outputdir/$output.tmp.m4a" "$outputdir/$output.a$mapindex.m4a"
			fi
		done		
		cmd_mux_audio=$(for ((mapindex=0; mapindex<$(ffmpeg-10bit -i "$input" 2>&1 | grep "Audio" | wc -l); ++mapindex)); do \
			printf ' --no-track-tags --no-chapters --language 0:'$MuxLang' ( '$outputdir'/'$output'.a'$mapindex'.m4a )'; done)
		cmd_mux_tail='--track-order 0:0'$(for ((mapindex=0; mapindex<$(ffmpeg-10bit -i "$input" 2>&1 | grep "Audio" | wc -l); ++mapindex)); do \
			printf ','$(($mapindex+1))':0'; done)
		if [ $(ffmpeg-10bit -i "$input" 2>&1 | grep "Subtitle" | wc -l) -gt 0 ]; then
			if [ -f "$outputdir/$output.subtmp.mkv" ]; then
				rm -f "$outputdir/$output.subtmp.mkv"
			fi
			if [ ! -f "$outputdir/$output.sub.mkv" ]; then
				ffmpeg-10bit -hide_banner \
					-v quiet \
					-i "$input" \
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
					for ((mapindex=0; mapindex<$(ffmpeg-10bit -i "$input" 2>&1 | grep "Audio" | wc -l); ++mapindex))
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
					for ((mapindex=0; mapindex<$(ffmpeg-10bit -i "$input" 2>&1 | grep "Audio" | wc -l); ++mapindex))
					do
						rm -f "$outputdir/$output.a$mapindex.m4a"
					done
				fi
			fi
		fi
	fi
}

if [ $# -lt 1 ]; then
	echo 用法:
	echo $(basename $0) video1 [video2] [video3]...
	echo
	echo TIPS:
	echo 1.注意如果路径中有空格的话需要用引号，如$(basename $0) \'/dir 1/1 1.avi\'或$(basename $0) \"/dir 2/2 2.flv\"
	echo 2.“理论上”支持find命令的正则表达式
	echo 3.支持通配符，如$(basename $0) \'/dir 1/*.avi\' $(basename $0) \"/dir 2/v*\" 即可匹配/dir 1目录下所有的avi文件以及/dir 2目录下所有的以v开头的文件
	echo 4.图形化界面下可以在终端输入$(basename $0)后，将文件从“资源管理器”中拖拽到终端上松开，选择“粘贴位置”，会自动将文件路径输入到终端，有空格会自动加引号
	exit
else
	IFS_OLD=$IFS
	IFS=$'\n'
	for files in "$@"
	do
		find $(dirname "$files") -name $(basename "$files") -type f | for line in $(cat)
		do
			IFS=$IFS_OLD
			compress "$line"
			IFS=$'\n'
		done
	done
fi
