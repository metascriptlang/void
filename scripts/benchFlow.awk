# The flow a bench row measures: submit is the CPU time of recording and submitting a frame, frame
# the wall time between frames, upload what reaches the GPU as data, count the scene's shape.
function flow(metric) {
	if (metric ~ /\.present\.ms$/) return "submit"
	if (metric ~ /\.frame\.ms$/) return "frame"
	if (metric ~ /\.(firstPaint\.ms|uploads|uploadBytes|firstPaintUploadBytes)$/) return "upload"
	return "count"
}
