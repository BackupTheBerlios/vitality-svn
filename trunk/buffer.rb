require 'Qt'
require 'textmodel'
require 'keyevent'

class CommandEditor < Qt::LineEdit
	# Creates a CommandEditor object
	# param parent, name: the QWidget's parent and name
	def initialize(editor, parent = nil, name = nil)
		super(parent, name)
		@editor = editor
	end
end

class EditorBuffer < TextView
	signals 'to_command_mode(QString*)'

	# Creates an EditorBuffer object
	# param parent, name: the QWidget's parent and name
	def initialize(parent = nil, name = nil)
		super(parent, nil)
		@mode = 'Command'
		@command = ""
		@clipboard = nil
		@undo_stack = []
		@redo_stack = []

		@selection_start_row = -1
		@handlers = {}
			
		map('<esc>') { command_mode() }
		map(':') { emit(to_command_mode(':')) }
		map('/') { emit(to_command_mode('/')) }
		map('h') { |params| move_cursor_left(params) }
		map('j') { |params| move_cursor_down(params) }
		map('k') { |params| move_cursor_up(params) }
		map('l') { |params| move_cursor_right(params) }
		map('0') { |params| move_cursor_to_start_of_line(params) }
		map('^') { |params| move_cursor_to_first_char_in_line(params) }
		map('$') { |params| move_cursor_to_end_of_line(params) }

		map('x') { delete_current_character(); command_mode() }

		map('%') { move_cursor_to_matching_bracket() }

		map('w') { |params| move_cursor_short_word_forward(params) }
		map('W') { |params| move_cursor_long_word_forward(params) }
		map('b') { |params| move_cursor_short_word_backward(params) }
		map('B') { |params| move_cursor_long_word_backward(params) }

		map('e') { |params| move_cursor_to_end_of_current_short_word(params) }
		map('E') { |params| move_cursor_to_end_of_current_long_word(params) }
		
		map('D') { delete_to_end_of_current_line() }
		map('J') { join_current_line_with_next() }

		map('p') { paste_at_cursor_position() if @clipboard != nil }

		map('i') { insert_mode() }
		map('a') { move_cursor_right(:mode => :move); insert_mode() }
		map('A') { move_cursor_to_end_of_line(:mode => :move); insert_mode() }
		map('o') { move_cursor_to_end_of_line(:mode => :move); insert_text_at_cursor("\n"); insert_mode() }
		map('O') { move_cursor_to_start_of_line(:mode => :move); move_cursor_up(:mode => :move); insert_text_at_cursor("\n"); move_cursor_up(:mode => :move); insert_mode() }

		map('G') { go_to_line(params[:multiplier], params) }

		map('v') { visual_mode() }
		
		map('g') do |params|
			if @command == 'gg'
				go_to_line(model.num_lines, params)
			else
				@continue = true
			end
		end

		map('y') do |params|
			if @command =~ /[0-9]*yy/
				yank_current_line(params[:multiplier])
			else
				@continue = true
			end
		end

		map('d') do |params|
			if @command =~ /[0-9]*dd/
				delete_current_line(params[:multiplier])
			else 
				@continue = true
			end
		end

		map('u') { model.text = @undo_stack.pop(); repaint_rows(nil) }
	end

	# Changes the mode of the editor to insert mode
	def insert_mode() 
		model.clear_selection
		@mode = 'Insert' 
	end 

	# Changes the mode of the editor to command mode
	def command_mode() 
		model.clear_selection
		@mode = 'Command' 
	end 

	# Changes the mode of the editor to visual mode
	def visual_mode() @mode = 'Visual' end 

	# Deletes the line at the cursor position
	def delete_current_line(num_lines = 1) 
		@undo_stack << model.text.dup()
		num_lines.times { model.remove_line(model.cursor_row) }
		#repaint_rows(model.cursor_row)
	end

	# Copies the line at the cursor position onto the clipboard
	def yank_current_line(num_lines = 1) 
		@clipboard = model.lines(model.cursor_row, num_lines)
	end

	# Gets the cursor position
	# Returns [para, index]
	def get_cursor_position()
		[model.cursor_row, model.cursor_col]
	end

	# Moves the cursor to the left by one position
	def move_cursor_left(params) 
		execute_command(model.cursor_row, model.cursor_col, model.cursor_row, model.cursor_col - (params[:multiplier] || 1), params)
	end

	# Moves the cursor to the right by one position
	def move_cursor_right(params) 
		execute_command(model.cursor_row, model.cursor_col, model.cursor_row, model.cursor_col + (params[:multiplier] || 1), params)
	end

	# Moves the cursor to the up by one position
	def move_cursor_up(params) 
		execute_command(model.cursor_row, model.cursor_col, model.cursor_row - (params[:multiplier] || 1), model.cursor_col, params)
	end

	# Moves the cursor to the down by one position
	def move_cursor_down(params) 
		execute_command(model.cursor_row, model.cursor_col, model.cursor_row + (params[:multiplier] || 1), model.cursor_col, params)
	end

	# Moves the cursor to the start of the current line
	def move_cursor_to_start_of_line(params) 
		execute_command(model.cursor_row, model.cursor_col, model.cursor_row, 0, params)
	end

	# Returns whether or not `curr' is a new word if `prev' was the previous character
	def small_word_boundary?(curr, prev) 
		curr !~ /\s/ && (((curr =~ /\w/) != (prev =~ /\w/)) or prev =~ /\s/)
	end

	# Returns whether or not `curr' is a new word if `prev' was the previous character
	def long_word_boundary?(curr, prev) 
		curr !~ /\s/ && prev =~ /\s/
	end

	# Moves the cursor to the first character in the next short word.
	# params addend: 1 for forward, -1 for backward
	# params block: takes current and prev characters, returns whether or not curr is a start of a word
	def move_cursor_by_word(addend, params, &boundary) 
		para, index = get_cursor_position()
		line = model.line(para)
		new_index = index + addend
		while new_index.between?(0, line.length) and not boundary.call(line[new_index, 1], line[new_index - 1, 1])
			new_index += addend 
		end
		execute_command(para, index, para, new_index, params) 
	end

	def move_cursor_short_word_forward(params)
		move_cursor_by_word(1, params) { |c, p| small_word_boundary?(c, p) }
	end

	def move_cursor_short_word_backward(params)
		move_cursor_by_word(-1, params) { |c, p| small_word_boundary?(c, p) }
	end

	def move_cursor_long_word_forward(params)
		move_cursor_by_word(1, params) { |c, p| long_word_boundary?(c, p) }
	end

	def move_cursor_long_word_backward(params)
		move_cursor_by_word(-1, params) { |c, p| long_word_boundary?(c, p) }
	end

	# Moves the cursor to the first character in the current line
	def move_cursor_to_first_char_in_line(params) 
		ix = model.line(model.cursor_row).index(/[^\s]/) # index of first non-space character
		execute_command(model.cursor_row, model.cursor_col, model.cursor_row, ix, params) if ix != nil
	end

	# Moves the cursor to the end of the current line
	def move_cursor_to_end_of_line(params) 
		execute_command(model.cursor_row, model.cursor_col, model.cursor_row, model.line(model.cursor_row).length, params)
	end

	# Pastes the clipboard's contents at the cursor position
	def paste_at_cursor_position()
		model.insert_text_at_cursor(@clipboard) 
	end

	# Moves the cursor to the specified line.  Lines start from 1.
	# param num: the line to move to
	def go_to_line(num, params) 
		execute_command(model.cursor_row, model.cursor_col, num - 1, model.cursor_col, params)
	end

	# Replaces all occurrences of a pattern in the buffer.  Replaces line-by-line.
	# param pattern: the pattern to search for
	# param replacement: the pattern to replace it with
	def global_substitute(pattern, replacement) 
		# make sure it's a Regexp because groups don't seem to work with a string
		pattern = Regexp.new(pattern) if pattern.is_a?(String)
		model.text = model.text.gsub(pattern, replacement)
	end

	# Changes a specific line's text
	# param para: the line's number
	# param text: the new text
	def change_line(para, line) 
		model.change_line(para, line)
		repaint_rows(para)
	end

	# Deletes from the cursor to the end of the current line
	def delete_to_end_of_current_line() 
		move_cursor_to_end_of_line(:mode => :delete)
	end

	# Executes a command that involves a movement (plain move, delete, select, yank, change)
	# param para: line number
	# param index: offset in the line
	# param params: :mode can be nil, :select, :yank, :delete, or :change
	def execute_command(line_from, index_from, line_to, index_to, params) 
		# todo make :mode = :move the default and get rid of nil
		if params[:mode] != :move and params[:mode] != :visual and params[:mode] != nil
			if line_from > line_to or (line_from == line_to and index_from > index_to)
				line_from, line_to = line_to, line_from
				index_from, index_to = index_to, index_from
			end
		end
		
		if params[:mode] != :visual
			model.clear_selection()
		end

		case params[:mode]
			when :delete, :yank
				@clipboard = model.get_range(line_from, index_from, line_to, index_to)
				if params[:mode] == :delete
					model.remove_range(line_from, index_from, line_to, index_to)
					repaint_rows(line_from)
					#todo shouldn't be able to directly repaint rows
					set_cursor_position(line_from, index_from) 
				end
			when :move, :visual, nil
				line_to = 0 if line_to < 0
				line_to = model.num_lines - 1 if line_to >= model.num_lines
				index_to = 0 if index_to < 0
				index_to = model.line(line_to).length if index_to > model.line(line_to).length
				model.set_cursor_position(line_to, index_to)
				if params[:mode] == :visual
					toggle_selection(line_from, index_from, line_to, index_to)
				end
		end
	end

	# Maps the specified 'key' (in a particular format) to the 'block'
	def map(key, &block)
		@handlers[key] = block 
	end

	# Qt event
	def keyPressEvent(e)
		str = KeyEvent.get_key_press_string(e)
	
		if @mode == 'Insert'
			case str
				when "<esc>" then command_mode()
				when "<backspace>" then model.backspace()
				when "<delete>" then model.delete_current_character()
				when "<enter>" then model.insert_text_at_cursor("\n")
				when "<left>" then move_cursor_left(:mode => :move)
				when "<s-left>" then move_cursor_left(:mode => :visual)
				when "<right>" then move_cursor_right(:mode => :move)
				when "<up>" then move_cursor_up(:mode => :move)
				when "<down>" then move_cursor_down(:mode => :move)
				when "<end>" then move_cursor_to_end_of_line(:mode => :move)
				when "<home>" then move_cursor_to_start_of_line(:mode => :move)
				when "<space>" then model.insert_text_at_cursor(" ")

				else 
					if str !~ /</
						model.insert_text_at_cursor(str)
					end
			end
		else
			params = {}
			params[:multiplier] = [1, @command.to_i].max # to_i returns 0 if there is no number
			if @mode == "Visual"
				params[:mode] = :visual 
			else
				params[:mode] = :delete if @command =~ /^[0-9]*d/
				params[:mode] = :yank if @command =~ /^[0-9]*y/
				params[:mode] = :change if @command =~ /^[0-9]*c/
			end

			@command << str
			if @handlers[str] != nil
				@continue = false
				@handlers[str].call(params)
				@command = "" if not @continue
			end
		end
	end
end

