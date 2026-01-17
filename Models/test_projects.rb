class TestProjects
    attr_accessor :id, :name

    def initialize(id: nil, name: '')
        @id = id
        @name = name
    end

    def to_hash
        {
            id: @id,
            name: @name
        }
    end
end
