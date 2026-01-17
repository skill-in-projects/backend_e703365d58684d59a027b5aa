require_relative '../Models/test_projects'

class TestController
    def initialize(db)
        @db = db
    end

    def set_search_path
        # Set search_path to public schema (required because isolated role has restricted search_path)
        # Using string concatenation to avoid C# string interpolation issues
        @db.exec('SET search_path = public, "' + '$' + 'user"')
    end

    def get_all
        # Set search_path to public schema (required because isolated role has restricted search_path)
        set_search_path
        result = @db.exec('SELECT "Id", "Name" FROM "TestProjects" ORDER BY "Id"')
        result.map do |row|
            {
                'Id' => row['Id'].to_i,
                'Name' => row['Name']
            }
        end
        # Do NOT catch generic Exception - let it bubble up to Sinatra error handler
        # PG::Error will be caught by Sinatra's error handler and sent to runtime error endpoint
    end

    def get_by_id(id)
        # Set search_path to public schema (required because isolated role has restricted search_path)
        set_search_path
        result = @db.exec_params('SELECT "Id", "Name" FROM "TestProjects" WHERE "Id" = $1', [id])
        return nil if result.ntuples == 0
        
        row = result[0]
        {
            'Id' => row['Id'].to_i,
            'Name' => row['Name']
        }
        # Do NOT catch generic Exception - let it bubble up to Sinatra error handler
    end

    def create(data)
        # Set search_path to public schema (required because isolated role has restricted search_path)
        set_search_path
        result = @db.exec_params('INSERT INTO "TestProjects" ("Name") VALUES ($1) RETURNING "Id", "Name"', [data['name']])
        row = result[0]
        {
            'Id' => row['Id'].to_i,
            'Name' => row['Name']
        }
        # Do NOT catch generic Exception - let it bubble up to Sinatra error handler
    end

    def update(id, data)
        # Set search_path to public schema (required because isolated role has restricted search_path)
        set_search_path
        result = @db.exec_params('UPDATE "TestProjects" SET "Name" = $1 WHERE "Id" = $2 RETURNING "Id", "Name"', [data['name'], id])
        return nil if result.ntuples == 0
        
        row = result[0]
        {
            'Id' => row['Id'].to_i,
            'Name' => row['Name']
        }
        # Do NOT catch generic Exception - let it bubble up to Sinatra error handler
    end

    def delete(id)
        # Set search_path to public schema (required because isolated role has restricted search_path)
        set_search_path
        result = @db.exec_params('DELETE FROM "TestProjects" WHERE "Id" = $1', [id])
        result.cmd_tuples > 0
        # Do NOT catch generic Exception - let it bubble up to Sinatra error handler
    end
end
