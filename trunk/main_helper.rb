require 'Qt'

class Editor < Qt::Widget

def start_double()
	puts "about to start stuff"
	w = WhiteboardMainWindow.new("magee1", 2627)
	w.resize(800, 400)
	w.show()
	w2 = WhiteboardMainWindow.new("magee2", 2628)
	w2.resize(800, 400)
	w2.show()
	w.start_server()
	puts "about to start client"
	STDOUT.flush
	w2.start_client("localhost", 2627)
	[w, w2]
end
