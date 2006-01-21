require 'Qt'
require 'range_list'

class TextView < Qt::ScrollView
	attr_reader :model

	# Creates a MageeTextEdit
	# param parent, name: The QWidget's parent and name
	def initialize(parent = nil, name = nil) 
		super(parent, name)
		viewport.set_w_flags(Qt::WNoAutoErase | Qt::WStaticContents)
		set_static_background(true)

		@invalid_rows = []
	
		@model = TextModel.new()
		@model.set_first_line_in_view_handler { first_line_in_view }
		@model.set_last_line_in_view_handler { last_line_in_view }
		@model.set_changed_handler { |invalid_rows| @invalid_rows = invalid_rows; repaint_contents(false) }

		set_enabled(true)
		set_focus_policy(Qt::Widget::StrongFocus)

		resize(500, 500)
	end

	def drawContents(p, x, y, w, h) 
		@invalid_rows.each do |line_num|
			next if !line_num_to_coord(line_num).between?(y, (y + h)) 

			x, y = 50, line_num_to_coord(line_num)
			
			p.fill_rect(0, y - font_metrics.ascent, width, font_metrics.height, Qt::Brush.new(Qt::gray))

			model.get_line_render_instructions(line_num).each do |i|
				p.set_pen(i[0])
				p.draw_text(x, y, i[1])
				x += font_metrics.width(i[1])
			end
		end
	end

	# Returns the display coordinate of line 'n'
	def line_num_to_coord(n)
		(n + 1) * font_metrics.height
	end
	
	# Returns the line number of the display y-coordinate 'y'
	def coord_to_line_num(y)
		y / font_metrics.height - 1
	end	

	def cursor_row() @model.cursor_row end
	def cursor_col() @model.cursor_col end
	
	# Returns the line number of the first visible line
	def first_line_in_view()
		coord_to_line_num(contents_y)
	end

	# Returns the line number of the last visible line
	def last_line_in_view()
		coord_to_line_num(contents_y + height)
	end

	# Returns the number of lines that are visible
	def num_lines_in_view()
		last_line_in_view() - first_line_in_view() + 1
	end

	def contentsMousePressEvent(e)
		row = coord_to_line_num(e.y)
		width = 0
		line = @text.line(row)
		col = 0
		(0...line.length).each do |i|
			col = i
			width += text_width(line[i, 1]) #@font_metrics.width(line[i,1])
			puts line[i,1]
			break if width >= e.x - 50
		end
		set_cursor_position(row, col)
		#repaint_rows
	end
end

# invariants: there is always at least one line
class TextModel
	attr_reader :text
	attr_reader :line_indices # only for testing
	attr_reader :cursor_row, :cursor_col

	StartContentX = 50

	def initialize(text = "") 
		self.text = text # call the text=() function rather than assigning the member directly

		@cursor_row = 0
		@cursor_col = 0
		@selection_start = -1
		@selection_end = -1

		@highlights = [[0, Qt::black]]
		
		@invalid_rows = []
	end
		
	def text=(text) 
		@text = text
		@line_indices = []
		(0...@text.length).each { |i| @line_indices << i if @text[i,1] == "\n" }
	end

	# Gets the index of the n'th newline character.
	def line_index(num)
		if num == 0
			return -1
		elsif num <= @line_indices.length
			return @line_indices[num - 1]
		elsif num == @line_indices.length + 1
			return @text.length
		else
			return -999 # todo
		end 
	end

	# Returns the index of 'row', 'col' in the single-dimensional array
	def index_of_position(row, col = 0)
		line_index(row) + col + 1
	end

	# Given an absolute index returns the line number and index
	def index_line_and_col(index) 
		i = 0
		i += 1 while index_of_position(i) <= index
		i -= 1
		[i, index - index_of_position(i)]
	end

	# Adds 'amount' to all line indices with a current value greater than or equal to 'threshold'
	def adjust_line_indices_after(threshold, amount) 
		@line_indices.map! { |l| l >= threshold ? l + amount : l }
	end

	# Removes the line numbered 'line_num'
	def remove_line(line_num)
		if @line_indices == []
			@text = ""
		else
			length = line_index(line_num + 1) - line_index(line_num)
			@text[line_index(line_num) + 1 .. line_index(line_num + 1)] = ""
			@line_indices.delete_at(line_num)
			(line_num...@line_indices.length).each { |i| @line_indices[i] -= length }
		end
	end

	# Removes from 'line_from', 'index_from' up to but not including 'line_to', 'index_to'
	def remove_range(line_from, index_from, line_to, index_to) 
		ix1 = index_of_position(line_from, index_from)
		ix2 = index_of_position(line_to, index_to)
		@text[ix1 ... ix2] = ""
		@line_indices.delete_if { |i| i.between?(ix1, ix2) }
		adjust_line_indices_after(ix2, -(ix2 - ix1))
	end

	# Gets text from 'line_from', 'index_from' up to but not including 'line_to', 'index_to'
	def get_range(line_from, index_from, line_to, index_to) 
		ix1 = index_of_position(line_from, index_from)
		ix2 = index_of_position(line_to, index_to)
		@text[ix1 ... ix2]
	end

	# Inserts text 'text' at line 'line', before column 'col'
	def insert_text(line, col, text) 
		index = index_of_position(line, col)
		@text.insert(index, text)
		i = 0
		i += 1 while i < @line_indices.length and @line_indices[i] < index
		(0...text.length).each do |c|
			if text[c,1] == "\n"
				@line_indices.insert(i, index + c)
				i += 1
			end
		end
		(i ... @line_indices.length).each { |i| @line_indices[i] += text.length }
	end

	# Changes the text of line 'line_num' to 'text
	def change_line(line_num, text) 
		raise "no newlines here yet please" if text =~ /\n/
	
		ix1, ix2 = line_index(line_num) + 1, line_index(line_num + 1)
		@text[ix1...ix2] = text
		(line_num...@line_indices.length).each { |i| @line_indices[i] += text.length - (ix2 - ix1) }
	end

	# Returns the line numbered 'num' (first line is 0)
	def line(num) lines(num, 1) end

	# Returns 'num' lines starting from line 'start'
	def lines(start, num) 
		@text[index_of_position(start)...index_of_position(start + num) - 1]
	end

	# Returns the number of lines
	def num_lines() @line_indices.length + 1 end

	def set_first_line_in_view_handler(&block) @first_line_in_view_handler = block end
	def set_last_line_in_view_handler(&block) @last_line_in_view_handler = block end
	def set_changed_handler(&block) @changed_handler = block end
	
	# stuff can be various things (document this)
	def emit_changed(stuff) 
		if stuff == nil
			@changed_handler.call(RangeList.new((0...num_lines)))
		else
			@changed_handler.call(RangeList.new(stuff))
		end
	end

	def first_line_in_view() @first_line_in_view_handler.call end
	def last_line_in_view() @last_line_in_view_handler.call end

	# Sets the cursor's position to 'row', 'col'
	def set_cursor_position(row, col)
		invalid_rows = [@cursor_row, row]
		@cursor_row, @cursor_col = row, col
		if @cursor_row < first_line_in_view
			set_contents_pos(0, line_num_to_coord(@cursor_row))
			emit_changed(nil)
		elsif @cursor_row > last_line_in_view
			set_contents_pos(0, line_num_to_coord(@cursor_row - num_lines_in_view))
			emit_changed(nil)
		end
	end

	# Inserts text at the cursor's current position and updates cursor
	def insert_text_at_cursor(text) 
		insert_text(@cursor_row, @cursor_col, text)
	
		if text.include?("\n")
			#todo what about multiple \n's
			@cursor_row += 1
			@cursor_col = 0
			#resize_contents(500, line_num_to_coord(@text.num_lines + 1))
			emit_changed(@cursor_row - 1)
		else
			@cursor_col += text.length
			emit_changed(@cursor_row)
		end
	end

	# Deletes the character before the cursor (like pressing backspace)
	def backspace() 
		#todo
		if @cursor_col > 0
			line = line(@cursor_row)
			line[@cursor_col - 1.. @cursor_col - 1] = ""
			change_line(@cursor_row, line)
			@cursor_col -= 1
			emit_changed(@cursor_row)
		end
	end

	# Deletes the character at the cursor (like pressing delete)
	def delete_current_character() 
		if @selection_start != -1
			l1, i1 = index_line_and_col(@selection_start)
			l2, i2 = index_line_and_col(@selection_end)
			remove_range(l1, i1, l2, i2)
			clear_selection
			emit_changed((l1...num_lines)) #todo
		else
			line = line(@cursor_row)
			line[@cursor_col.. @cursor_col] = ""
			change_line(@cursor_row, line)
			emit_changed(@cursor_row)
		end
	end

	# Highlights all instances of 'pattern' in the text
	def highlight(pattern)
		pattern = Regexp.new(pattern) if pattern.is_a?(String)
		@highlights = [[0, Qt::black]] # todo factor this
		invalid_rows = []
		(0...num_lines).each do |index|
			line = line(index)
			if line =~ pattern
				#todo
				#@highlights << HighlightData.new(index, $~.begin(0), index, $~.end(0), Qt::yellow, Qt::black)
				#invalid_rows << index
			end
		end

		##repaint_rows(invalid_rows)
	end

	def clear_selection()
		if @selection_start != -1
			ss, se = @selection_start, @selection_end
			@selection_start = @selection_end = -1 
			@highlights.delete_if { |i| i.length == 3 }

			emit_changed((index_line_and_col(ss)[0]..index_line_and_col(se)[0]))
		end
	end
	
	def toggle_selection(start_line, start_index, end_line, end_index)
		# assume start_line, start_index = one of the borders
	
		ix1 = index_of_position(start_line, start_index)
		ix2 = index_of_position(end_line, end_index)
		
		if @selection_start == -1 or @selection_start == @selection_end
			@selection_start, @selection_end = [ix1, ix2].sort
		else
			if ix1 >= @selection_end
				@selection_end = ix2
			elsif ix1 <= @selection_start
				@selection_start, @selection_end = ix2, @selection_end
			else
				raise "this shouldn't happen"
			end
		end

		@highlights.delete_if { |i| i.length == 3 }
		@highlights << [@selection_start, Qt::yellow, 1] if @selection_start != @selection_end 
		@highlights << [@selection_end, Qt::black, 1]
		@highlights.sort! { |x, y| x[0] <=> y[0] }

		#repaint_rows(start_line, end_line) 
	end

	# Returns a 2D array [[render1, text1], [render2, text2], ..., [rendern, textn]]
	def get_line_render_instructions(line_num)
		start_line_index = index_of_position(line_num)
		line = line(line_num)

		instructions = []

		highlight_index = @highlights.length - 1
		highlight_index -= 1 while highlight_index > 0 and @highlights[highlight_index][0] > start_line_index
		highlight = @highlights[highlight_index][1]
		highlight_index += 1
		part_start_index = 0

		(0..line.length).each do |c|
			if c == line.length or (highlight_index < @highlights.length and @highlights[highlight_index][0] == c + start_line_index)
				instructions << [highlight, line[part_start_index ... c]]
				break if c == line.length
				highlight = @highlights[highlight_index][1]
				highlight_num += 1
			end
		end

		instructions
	end
			

#		# draw cursor
#		#w = StartContentX
#		#w += @font_metrics.width(@text.line(@cursor_row)[0 ... @cursor_col].gsub("\t", '  ')) if @text.num_lines > 0
#		#p.draw_line(w, line_num_to_coord(@cursor_row) - font_metrics.ascent(), w, line_num_to_coord(@cursor_row))
#		#draw_cursor(@cursor_row, @cursor_col)

end
