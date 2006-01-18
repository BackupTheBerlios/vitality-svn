require 'Qt'
require 'editorui'
require 'buffer'

class Editor < EditorUI
	slots 'execute_command()', 'command_mode(QString*)'

	# Create a new Editor object
	# param parent: the QWidget's parent
	def initialize(parent)
		super(parent)
		connect(@command_editor, SIGNAL('returnPressed()'), SLOT('execute_command()')) 
		connect(@editor, SIGNAL('command_mode(QString*)'), SLOT('command_mode(QString*)'))

		#@line_numbers.text = (1..20).to_a().map { |i| i.to_s }.join("\n")

		@editor.set_focus()
	end

	# Execute the command entered into the command window
	def execute_command() 
		text = @command_editor.text

		if text =~ %r{%s/([^/]*)/([^/]*)/g}
			@editor.global_substitute($1, $2)
		elsif text =~ %r{/(.*)}
			@editor.highlight($1)
		elsif text =~ /:e (.*)/
			File.open($1, "r") do |f|
				@editor.text = f.read()
			end
		elsif text =~ /:w (.*)/
			File.open($1, "w+") do |f|
				f.write(@editor.text)
			end
		else
			@editor.instance_eval(@command_editor.text)
		end
		@editor.set_focus()
	end

	# Enters command mode (gives the command textbox focus)
	def command_mode(s) 
		@command_editor.set_text(s)
		@command_editor.set_focus()
	end

	# Enters insert mode (focuses the editor textbox)
	def insert_mode() 
		@editor.set_focus()
	end
end

s = Qt::SizePolicy.new()

a = Qt::Application.new(ARGV)
w = Editor.new(nil)
w.show()
a.set_main_widget(w)
a.exec()
