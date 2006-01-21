class RangeList < Array
	def initialize(*args)
		args.each { |i| self << i }	
	end
	
	def each(&block)
		super do |i|
			if i.is_a?(Range)
				i.each { |ri| block.call(ri) }
			else
				block.call(i)
			end
		end
	end
end
