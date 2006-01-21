require 'test/unit'
require 'textedit'

# comment
# param (type): description
def test_text_invariant(t)
	t1 = t.text.gsub("\n", "\\n")
	rep = "line indices: [#{t.line_indices.join(', ')}], text = #{t1}"

	assert(t.text.gsub(/[^\n]/, '').length == t.line_indices.length, "Incorrect number of newlines: #{rep}")
	assert(t.line_indices == t.line_indices.sort)
	t.line_indices.each do |i| 
		assert(t.text[i,1] == "\n", "line_indices false positive: #{rep}")
	end
end


class TestText < Test::Unit::TestCase
	def test_set_text() 
		t = Text.new()
		test_text_invariant(t)
		assert_equal([], t.line_indices)
		
		t.text = "hello\nbello\ncello"
		test_text_invariant(t)
		assert_equal([5, 11], t.line_indices) 

		t.text = "\n\n\n"
		test_text_invariant(t)
		assert_equal([0, 1, 2], t.line_indices)

		t.text = ""
		test_text_invariant(t)
		assert_equal([], t.line_indices)
	end	

	def test_remove_line()
		t = Text.new("hello\nbello\ncello")
		test_text_invariant(t)
		
		t.remove_line(0)
		test_text_invariant(t)
		assert_equal("bello\ncello", t.text)

		t.remove_line(0)
		test_text_invariant(t)
		assert_equal("cello", t.text)

		t.remove_line(0)
		test_text_invariant(t)
		assert_equal("", t.text)

		t.text = "\n\n\n"
		t.remove_line(1)
		test_text_invariant(t)
		assert_equal("\n\n", t.text)

		t.text = "hello this is longer\nwith three lines\nthis is the third line"
		t.remove_line(2)
		test_text_invariant(t)
		assert_equal("hello this is longer\nwith three lines\n", t.text)

		t.remove_line(1)
		test_text_invariant(t)
		assert_equal("hello this is longer\n", t.text)

		t.remove_line(0)
		test_text_invariant(t)
		assert_equal("", t.text)

		t.text = "now we remove\nfrom the middle line\nof three lines"
		t.remove_line(1)
		test_text_invariant(t)
		assert_equal("now we remove\nof three lines", t.text)
	end

	def test_insert_text() 
		t = Text.new("here is some\ntext with some\nnewlines in it")
		t.insert_text(0, 0, "\n")
		test_text_invariant(t)
		assert_equal("\nhere is some\ntext with some\nnewlines in it", t.text)

		t.insert_text(1, 5, "\n")
		test_text_invariant(t)
		assert_equal("\nhere \nis some\ntext with some\nnewlines in it", t.text)
		
		t.insert_text(4, 5, "\n")
		test_text_invariant(t)
		assert_equal("\nhere \nis some\ntext with some\nnewli\nnes in it", t.text)

		t.insert_text(3, 3, "b")
		test_text_invariant(t)
		assert_equal("\nhere \nis some\ntexbt with some\nnewli\nnes in it", t.text)
		
		t.insert_text(3, 7, "")
		test_text_invariant(t)
		assert_equal("\nhere \nis some\ntexbt with some\nnewli\nnes in it", t.text)

		t.text = "something nicer\nbut not that nice"
		t.insert_text(0, 5, "some text\nwith a newline in")
		test_text_invariant(t)
		assert_equal("sometsome text\nwith a newline inhing nicer\nbut not that nice", t.text)
	end

	def test_change_line() 
		t = Text.new("hello bro\nwe have three lines\nagain")
		t.change_line(0, "bye bye bro")
		test_text_invariant(t)
		assert_equal("bye bye bro\nwe have three lines\nagain", t.text)
	end

	def test_remove_range() 
		t = Text.new("we are going to\nremove a range\nfrom this text")
		t.remove_range(0, 5, 2, 9)
		test_text_invariant(t)
		assert_equal("we ar text", t.text)

		t.remove_range(0, 0, 0, 0)
		test_text_invariant(t)
		assert_equal("we ar text", t.text)
		
		t.remove_range(0, 0, 0, 1)
		test_text_invariant(t)
		assert_equal("e ar text", t.text)

		t.text = "just try removing stuff but\nnot any lines"
		test_text_invariant(t)
		t.remove_range(0, 3, 0, 8)
		test_text_invariant(t)
		assert_equal("jus removing stuff but\nnot any lines", t.text)
	end
	
	def test_index()
		t = Text.new("hello and you are a head\nof a cheese and beef\nthis is nonsense")
		assert_equal(0, t.index_of_position(0, 0))
		assert_equal([0, 0], t.index_line_and_col(0))
		assert_equal(1, t.index_of_position(0, 1))
		assert_equal([0, 1], t.index_line_and_col(1))
		assert_equal(1, t.index_of_position(0, 1))
		assert_equal([0, 1], t.index_line_and_col(1))
	end
end
