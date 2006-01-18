require 'Qt'
require 'textedit'

class CommandEditor < Qt::LineEdit
	# Creates a CommandEditor object
	# param editor: a BufferEditor object that this object controls
	# param parent, name: the QWidget's parent and name
	def initialize(editor, parent = nil, name = nil)
		super(parent, name)
		@editor = editor
	end
end

class EditorBuffer < MageeTextEdit
	signals 'command_mode(QString*)'

	# Creates an EditorBuffer object
	# param parent, name: the QWidget's parent and name
	def initialize(parent = nil, name = nil)
		super(parent, nil)
		@mode = 'Command'
		@command = ""
		@clipboard = nil
		@undo_stack = []
		@redo_stack = []
	end

	# Inserts text at the current cursor position
	# param text: the text to insert
	def insert_text(text)
		insert(text)	
	end

	# Deletes the line at the cursor position
	def delete_current_line() 
		@undo_stack << @text.text.dup()
		remove_line(@cursor_row)
	end

	# Copies the line at the cursor position onto the clipboard
	def yank_current_line() 
		@clipboard = @lines[@cursor_row].dup()
	end

	# Gets the cursor position
	# Returns [para, index]
	def get_cursor_position()
		[@cursor_row, @cursor_col]
	end

	# Moves the cursor to the left by one position
	def move_cursor_left(params) 
		para, index = get_cursor_position()
		new_index = index - (params[:multiplier] || 1)
		execute_command(para, index, para, new_index, params)
	end

	# Moves the cursor to the right by one position
	def move_cursor_right(params) 
		para, index = get_cursor_position()
		new_index = index + (params[:multiplier] || 1)
		execute_command(para, index, para, new_index, params)
	end

	# Moves the cursor to the up by one position
	def move_cursor_up(params) 
		para, index = get_cursor_position()
		new_para = para - (params[:multiplier] || 1)
		execute_command(para, index, new_para, index, params)
	end

	# Moves the cursor to the down by one position
	def move_cursor_down(params) 
		para, index = get_cursor_position()
		new_para = para + (params[:multiplier] || 1)
		execute_command(para, index, new_para, index, params)
	end

	# Moves the cursor to the start of the current line
	def move_cursor_to_start_of_line(params) 
		para, index = get_cursor_position()
		execute_command(para, index, para, 0, params)
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
		line = @text.line(para)
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
		para, index = get_cursor_position()
		ix = @text.line(para).index(/[^\s]/) # index of first non-space character
		execute_command(para, index, para, ix, params) if ix != nil
	end

	# Moves the cursor to the end of the current line
	def move_cursor_to_end_of_line(params) 
		para, index = get_cursor_position()
		execute_command(para, index, para, @text.line(para).length, params)
	end

	# Pastes the clipboard's contents at the cursor position
	def paste_at_cursor_position()
		insert_text_at_cursor(@clipboard) 
	end

	# Moves the cursor to the specified line.  Lines start from 1.
	# param num: the line to move to
	def go_to_line(num, params) 
		para, index = get_cursor_position()
		execute_command(para, index, num - 1, index, params)
	end

	# Replaces all occurrences of a pattern in the buffer.  Replaces line-by-line.
	# param pattern: the pattern to search for
	# param replacement: the pattern to replace it with
	def global_substitute(pattern, replacement) 
		# make sure it's a Regexp because groups don't seem to work with a string
		pattern = Regexp.new(pattern) if pattern.is_a?(String)
		@text.text = @text.text.gsub(pattern, replacement)
	end

	# Changes a specific line's text
	# param para: the line's number
	# param text: the new text
	def change_line(para, line) 
		@text.change_line(para, line)
		repaint_rows([para])
	end

	# Deletes from the cursor to the end of the current line
	def delete_to_end_of_current_line() 
		move_cursor_to_end_of_line(:mode => :delete)
	end

	# Executes a command that involves a movement (plain move, delete, select, yank, change)
	# param para: line number
	# param index: offset in the line
	# param params: :mode can be nil, :select, :yank, :delete, or :change
	def execute_command(para_from, index_from, para_to, index_to, params) 
		case params[:mode]
			when :delete, :yank
				if para_from > para_to or (para_from == para_to and index_from > index_to)
					para_from, para_to = para_to, para_from
					index_from, index_to = index_to, index_from
				end

				if para_from == para_to
					@clipboard = @text.line(para_from)[index_from .. index_to - 1]
					if params[:mode] == :delete
						line = @text.line(para_from)
						line[index_from .. index_to - 1] = ""
						@text.change_line(para_from, line)
						repaint_rows([para_from])
					end
				else
					@clipboard = @text.line(para_from)[index_from .. -1]
					(para_from + 1).upto(para_to - 1) { |i| @clipboard << @text.line(i) }
					@clipboard << @text.line(para_to)[0 .. index_to - 1] if index_to > 0

					if params[:mode] == :delete
						current_line = @text.line(para_to)[index_to .. - 1]
						current_line = @text.line(para_from)[0 .. index_from - 1] + current_line if index_from > 0
						change_line(para_from, current_line)
						(para_to - para_from).times { remove_line(para_from + 1) }
					end
				end
				if params[:mode] == :delete
					set_cursor_position(para_from, index_from) 
				end
			when :move, nil
				para_to = 0 if para_to < 0
				para_to = @text.num_lines - 1 if para_to >= @text.num_lines
				index_to = 0 if index_to < 0
				index_to = @text.line(para_to).length if index_to > @text.line(para_to).length
				set_cursor_position(para_to, index_to)
		end
	end

	# Qt event
	def keyPressEvent(e)
		if @mode == 'Insert'
			case e.key
				when Qt::Key_Escape then @mode = 'Command'
				when Qt::Key_Backspace then backspace()
				when Qt::Key_Delete then delete_current_character()
				when Qt::Key_Return then insert_text_at_cursor("\n")
				else puts e.ascii.chr; insert_text_at_cursor(e.ascii.chr)
			end
		else
			params = {}
			params[:multiplier] = [1, @command.to_i].max # to_i returns 0 if there is no number
			params[:mode] = :delete if @command =~ /^[0-9]*d/
			params[:mode] = :select if @command =~ /^[0-9]*v/
			params[:mode] = :yank if @command =~ /^[0-9]*y/
			params[:mode] = :change if @command =~ /^[0-9]*c/

			@command << e.text
			case e.text
				when ':', '/' then emit(command_mode(e.text))
				when 'h' then move_cursor_left(params); @command = ""
				when 'j' then move_cursor_down(params); @command = ""
				when 'k' then move_cursor_up(params); @command = ""
				when 'l' then move_cursor_right(params); @command = ""
				when '0' then move_cursor_to_start_of_line(params); @command = ""
				when '^' then move_cursor_to_first_char_in_line(params); @command = ""
				when '$' then move_cursor_to_end_of_line(params); @command = ""

				when 'x' then delete_current_character(); @command = ""

				when '%' then move_cursor_to_matching_bracket(params); @command = ""

				when 'w' then move_cursor_short_word_forward(params); @command = ""
				when 'W' then move_cursor_long_word_forward(params); @command = ""
				when 'b' then move_cursor_short_word_backward(params); @command = ""
				when 'B' then move_cursor_long_word_backward(params); @command = ""
				
				when 'D' then delete_to_end_of_current_line(); @command = ""
				when 'J' then join_current_line_with_next(); @command = ""

				when 'p' then paste_at_cursor_position() if @clipboard != nil; @command = ""

				when 'i' then @mode = 'Insert'; @command = ""
				when 'a' then move_cursor_right(params); @mode = 'Insert'; @command = ""
				when 'A' then move_cursor_to_end_of_line(:mode => :move); @mode = 'Insert'; @command = ""
				when 'o' then move_cursor_to_end_of_line(:mode => :move); 
					insert_text_at_cursor("\n"); @mode = 'Insert'; @command = ""
				when 'O' then move_cursor_to_start_of_line(:mode => :move); move_cursor_up(:mode => :move); 
					insert_text_at_cursor("\n"); move_cursor_up(:mode => :move); @mode = 'Insert'; @command = ""

				when 'G' then go_to_line(@command.to_i, params); @command = ""
				when 'g' then (go_to_line(@text.num_lines, params); @command = "") if @command == 'gg'

				when 'y' then (yank_current_line(); @command = "") if @command == 'yy'
				when 'd' then (delete_current_line(); @command = "") if @command == 'dd'

				when 'u' then @text.text = @undo_stack.pop(); repaint_rows(nil); @command = ""
			end
		end
	end
end

