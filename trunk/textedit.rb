require 'Qt'

class HighlightData
	attr_reader :start_row, :start_col, :end_row, :end_col, :fgcolor, :bgcolor
	
	def initialize(start_row, start_col, end_row, end_col, fgcolor, bgcolor)
		@start_row, @start_col, @end_row, @end_col, @fgcolor, @bgcolor =  
			start_row, start_col, end_row, end_col, fgcolor, bgcolor
	end
end

# invariant: @line_indices = [i : @text[i] == '\n']
class Text
	attr_reader :text
	attr_reader :line_indices # only for testing

	def initialize(text = "") 
		self.text = text
	end

	def text=(text) 
		@text = text
		@line_indices = []
		(0...@text.length).each { |i| @line_indices << i if @text[i,1] == "\n" }
	end

	# comment
	# param (type): description
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

	# Adds 'amount' to all line indices with a current value greater than or equal to 'threshold'
	def adjust_line_indices_after(threshold, amount) 
		@line_indices.each { |l| l += amount if l >= threshold }
	end

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
	def line(num) @text[index_of_position(num)...index_of_position(num + 1) - 1] end

	# Returns the number of lines
	def num_lines() @line_indices.length + 1 end
end

# invariants: there is always at least one line
class MageeTextEdit < Qt::ScrollView
	attr_reader :cursor_row, :cursor_col, :lines

	# Creates a MageeTextEdit
	# param parent, name: The QWidget's parent and name
	def initialize(parent = nil, name = nil) 
		super(parent, name)
		viewport.set_w_flags(Qt::WNoAutoErase | Qt::WStaticContents)
		set_static_background(true)

		@text = Text.new()

		fm = Qt::FontMetrics.new(font())
		@text_height = fm.height()

		@cursor_row = 0
		@cursor_col = 0
		@selection_start_row = -1
		@selection_start_col = -1
		@selection_end_row = -1
		@selection_end_col = -1

		@highlights = []
		@invalid_rows = []

		set_enabled(true)
		set_focus_policy(Qt::Widget::StrongFocus)
		
		repaint_rows(nil)
	end

	def text() @text.text end 
	def text=(s) 
		@text.text = s; 
		repaint_rows(nil) 
		resize_contents(500, @text_height * @text.num_lines + 20)
	end 

	# Repaints the specified rows, where rows is an array containing integers and/or ranges, or nil to 
	# indicate repainting the entire document
	def repaint_rows(rows) 
		@invalid_rows = rows
		repaint_contents(false)
	end

	def set_cursor_position(row, col)
		invalid_rows = [@cursor_row, row]
		@cursor_row, @cursor_col = row, col
		repaint_rows(invalid_rows)
	end


	# Inserts text at the cursor's current position and updates cursor
	def insert_text_at_cursor(text) 
		@text.insert_text(@cursor_row, @cursor_col, text)
	
		if text == "\n"
			invalid_rows = (@cursor_row ... @text.num_lines)
			@cursor_row += 1
			@cursor_col = 0
			resize_contents(500, @text_height * (@text.num_lines + 1))
		else
			invalid_rows = [@cursor_row]
			@cursor_col += text.length
		end
		repaint_rows(invalid_rows)
	end

	# Deletes the character before the cursor (like pressing backspace)
	def backspace() 
		line = @text.line(@cursor_row)
		line[@cursor_col - 1.. @cursor_col - 1] = ""
		@text.change_line(@cursor_row, line)
		@cursor_col -= 1
		repaint_rows([@cursor_row])
	end

	# Deletes the character at the cursor (like pressing delete)
	def delete_current_character() 
		line = @text.line(@cursor_row)
		line[@cursor_col.. @cursor_col] = ""
		@text.change_line(@cursor_row, line)
		repaint_rows([@cursor_row])
	end

	# Sets the graphics object appropriately to display the HighlightData object passed.
	# highlight can be nil in which case normal text will be drawn
	def set_highlight(graphics, highlight)
		if highlight == nil
			graphics.set_background_mode(Qt::TransparentMode)
			graphics.set_pen(Qt::black)
		else
			graphics.set_background_mode(Qt::OpaqueMode)
			graphics.set_background_color(highlight.bgcolor)
			graphics.set_pen(highlight.fgcolor)
		end
	end

	# Highlights all instances of 'pattern' in the text
	def highlight(pattern)
		pattern = Regexp.new(pattern) if pattern.is_a?(String)
		@highlights = []
		invalid_rows = []
		(0...@text.num_lines).each do |index|
			line = @text.line(index)
			if line =~ pattern
				@highlights << HighlightData.new(index, $~.begin(0), index, $~.end(0), Qt::yellow, Qt::black)
				invalid_rows << index
			end
		end

		repaint_rows(invalid_rows)
	end

	# Paints the text.  By default only paints lines marked in invalid_rows unless invalid_rows = nil
	def paint_text(p, invalid_rows = nil)
		set_highlight(p, nil)

		fm = Qt::FontMetrics.new(font())

		highlights_and_selection = @highlights + [HighlightData.new(@selection_start_row,
			@selection_start_col, @selection_end_row, @selection_end_col, Qt::white, Qt::blue)]
		current_highlight = nil

		start_content_x = 50

		line_numbers = []
		if invalid_rows != nil
			invalid_rows.each do |i|
				if i.is_a?(Range)
					i.each { |n| line_numbers << n }
				else
					line_numbers << i
				end
			end
		else
			line_numbers = (0...@text.num_lines).to_a #not very nice at all
		end
		
		line_numbers.each do |i|
			s = @text.line(i)
		
			highlight = highlights_and_selection.find { |h| h.start_row == i }
			p.fill_rect(0, @text_height * (i + 1) - font_metrics.ascent(), viewport.width, @text_height, Qt::Brush.new(Qt::gray))
			t = TextDrawer.new(p, fm, start_content_x, @text_height * (i + 1))
			if highlight != nil
				t.draw_text(s[0 ... highlight.start_col])
				set_highlight(p, highlight)
				if i == highlight.end_row
					t.draw_text(s[highlight.start_col ... highlight.end_col])
					set_highlight(p, nil)
					t.draw_text(s[highlight.end_col .. -1])
				else
					t.draw_text(s[highlight.start_col .. -1])
					current_highlight = highlight
				end
			elsif current_highlight != nil and i == current_highlight.end_row
				t.draw_text(s[0 ... current_highlight.end_col])
				set_highlight(p, nil)
				t.draw_text(s[current_highlight.end_col .. -1])
			else
				t.draw_text(s)
			end
		
			# todo worry about highlight	
			p.draw_text(0, (i + 1) * @text_height, (i + 1).to_s)
		end

		w = start_content_x
		w += fm.width(@text.line(@cursor_row)[0 ... @cursor_col].gsub("\t", '  ')) if @text.num_lines > 0
		p.draw_line(w, @text_height * (@cursor_row + 1) - font_metrics.ascent(), w, @text_height * (@cursor_row + 1))

		@invalid_rows = nil
	end

	# Qt event	
	def drawContents(p, x, y, w, h) 
		paint_text(p, @invalid_rows)
	end
end

class TextDrawer
	def initialize(painter, font_metrics, x, y)
		@painter, @font_metrics, @x, @y = painter, font_metrics, x, y 
	end

	def draw_text(text)
		@painter.draw_text(@x, @y, text.gsub("\t", '  '))
		@x += @font_metrics.width(text)
	end
end
