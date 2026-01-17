require 'sinatra'
require 'pg'
require 'json'
require 'logger'
require_relative 'Controllers/test_controller'

# Configure logging - Warning and Error only
LOG_LEVEL = ENV['LOG_LEVEL'] || 'WARN'
logger = Logger.new(STDOUT)
logger.level = Logger.const_get(LOG_LEVEL)
logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{severity}] #{datetime}: #{msg}\n"
end

# Use logger in Sinatra
set :logger, logger

# Configure Sinatra to use custom error handler (not show_exceptions)
set :show_exceptions, false  # Disable default error page
set :raise_errors, false     # Don't re-raise errors, use error handler instead

# Port and bind settings - Puma config file (puma.rb) will override these
# But we set them here as fallback
set :port, (ENV['PORT'] || 8080).to_i
set :bind, '0.0.0.0'

# CORS headers
before do
    headers 'Access-Control-Allow-Origin' => '*',
            'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS',
            'Access-Control-Allow-Headers' => 'Content-Type'
end

options '*' do
    200
end

# Global error handler for all exceptions
# This catches ALL exceptions, including those raised in routes
error do
    exception = env['sinatra.error']
    logger.error("[ERROR HANDLER] Unhandled exception occurred: #{exception.message}")
    logger.error("[ERROR HANDLER] Exception class: #{exception.class}")
    logger.error(exception.backtrace.join("\n")) if exception.backtrace
    
    # Extract boardId from request
    board_id = extract_board_id(request)
    logger.warn("[ERROR HANDLER] Extracted boardId: #{board_id || 'NULL'}")
    
    # Send error to runtime error endpoint if configured
    runtime_error_endpoint_url = ENV['RUNTIME_ERROR_ENDPOINT_URL']
    logger.warn("[ERROR HANDLER] RUNTIME_ERROR_ENDPOINT_URL: #{runtime_error_endpoint_url || 'NOT SET'}")
    
    if runtime_error_endpoint_url && !runtime_error_endpoint_url.empty?
        logger.warn("[ERROR HANDLER] Sending error to endpoint: #{runtime_error_endpoint_url} (boardId: #{board_id || 'NULL'})")
        # Use Thread.new for fire-and-forget, but ensure it doesn't die silently
        Thread.new do
            begin
                send_error_to_endpoint(runtime_error_endpoint_url, board_id, request, exception)
            rescue => e
                logger.error("[ERROR HANDLER] Failed to send error to endpoint: #{e.message}")
                logger.error("[ERROR HANDLER] Error backtrace: #{e.backtrace.join("\n")}") if e.backtrace
            end
        end
    else
        logger.warn("[ERROR HANDLER] RUNTIME_ERROR_ENDPOINT_URL is not set - skipping error reporting")
    end
    
    # Return error response
    status 500
    content_type :json
    { error: 'An error occurred while processing your request', message: exception.message }.to_json
end

def extract_board_id(request)
    # Try query parameter
    return params['boardId'] if params['boardId']
    
    # Try header
    return request.env['HTTP_X_BOARD_ID'] if request.env['HTTP_X_BOARD_ID']
    
    # Try environment variable
    board_id = ENV['BOARD_ID']
    return board_id if board_id && !board_id.empty?
    
    # Try to extract from hostname (Railway pattern: webapi{boardId}.up.railway.app - no hyphen)
    host = request.host
    if host && (match = host.match(/webapi([a-f0-9]{24})/i))
        return match[1]
    end
    
    # Try to extract from RUNTIME_ERROR_ENDPOINT_URL if it contains boardId pattern
    endpoint_url = ENV['RUNTIME_ERROR_ENDPOINT_URL'] || ''
    if (match = endpoint_url.match(/webapi([a-f0-9]{24})/i))
        return match[1]
    end
    
    nil
end

def send_error_to_endpoint(endpoint_url, board_id, request, exception)
    require 'net/http'
    require 'uri'
    require 'json'
    
    # Get stack trace
    stack_trace = exception.backtrace ? exception.backtrace.join("\n") : 'N/A'
    
    # Get file and line from backtrace
    first_line = exception.backtrace ? exception.backtrace.first : nil
    file_name = nil
    line_number = nil
    if first_line && (match = first_line.match(/(.+):(\d+):/))
        file_name = match[1]
        line_number = match[2].to_i
    end
    
    # Ensure boardId is a string (not nil) - C# endpoint requires non-null
    board_id_str = board_id.nil? ? '' : board_id.to_s
    
    payload = {
        boardId: board_id_str,
        timestamp: Time.now.utc.iso8601,
        file: file_name || '',
        line: line_number,
        stackTrace: stack_trace || 'N/A',
        message: exception.message || 'Unknown error',
        exceptionType: exception.class.name || 'Exception',
        requestPath: request.path || '/',
        requestMethod: request.request_method || 'GET',
        userAgent: request.user_agent || ''
    }.to_json
    
    uri = URI(endpoint_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = 5
    http.read_timeout = 5
    
    request_obj = Net::HTTP::Post.new(uri.path)
    request_obj['Content-Type'] = 'application/json'
    request_obj.body = payload
    
    begin
        response = http.request(request_obj)
        if response.code.to_i != 200
            logger.warn("[ERROR HANDLER] Error endpoint response: #{response.code} - #{response.body}")
        else
            logger.warn("[ERROR HANDLER] Error endpoint response: #{response.code}")
        end
    rescue => e
        logger.error("[ERROR HANDLER] Failed to send error to endpoint: #{e.message}")
        logger.error("[ERROR HANDLER] Error backtrace: #{e.backtrace.join("\n")}") if e.backtrace
    end
end

# Database connection
def get_db
    database_url = ENV['DATABASE_URL']
    raise 'DATABASE_URL environment variable not set' unless database_url
    
    PG.connect(database_url)
end

# Helper to parse JSON body
def parse_json_body
    request.body.rewind
    JSON.parse(request.body.read)
rescue JSON::ParserError
    {}
end

# Root endpoint
get '/' do
    content_type :json
    {
        message: 'Backend API is running',
        status: 'ok',
        swagger: '/swagger',
        api: '/api/test'
    }.to_json
end

# Health check
get '/health' do
    content_type :json
    {
        status: 'healthy',
        service: 'Backend API'
    }.to_json
end

# Swagger UI endpoint - serve interactive Swagger UI HTML page
get '/swagger' do
    content_type :html
    <<-HTML
<!DOCTYPE html>
<html>
<head>
    <title>Backend API - Swagger UI</title>
    <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@5.9.0/swagger-ui.css" />
    <style>
        html { box-sizing: border-box; overflow: -moz-scrollbars-vertical; overflow-y: scroll; }
        *, *:before, *:after { box-sizing: inherit; }
        body { margin:0; background: #fafafa; }
    </style>
</head>
<body>
    <div id="swagger-ui"></div>
    <script src="https://unpkg.com/swagger-ui-dist@5.9.0/swagger-ui-bundle.js"></script>
    <script src="https://unpkg.com/swagger-ui-dist@5.9.0/swagger-ui-standalone-preset.js"></script>
    <script>
        window.onload = function() {
            const ui = SwaggerUIBundle({
                url: "/swagger.json",
                dom_id: "#swagger-ui",
                deepLinking: true,
                presets: [
                    SwaggerUIBundle.presets.apis,
                    SwaggerUIStandalonePreset
                ],
                plugins: [
                    SwaggerUIBundle.plugins.DownloadUrl
                ],
                layout: "StandaloneLayout"
            });
        };
    </script>
</body>
</html>
    HTML
end

# Swagger JSON endpoint - return OpenAPI spec as JSON
get '/swagger.json' do
    content_type :json
    {
        openapi: '3.0.0',
        info: {
            title: 'Backend API',
            version: '1.0.0',
            description: 'Ruby Backend API Documentation'
        },
        paths: {
            '/api/test' => {
                get: {
                    summary: 'Get all test projects',
                    responses: {
                        '200' => {
                            description: 'List of test projects',
                            content: {
                                'application/json' => {
                                    schema: {
                                        type: 'array',
                                        items: { '$ref' => '#/components/schemas/TestProjects' }
                                    }
                                }
                            }
                        }
                    }
                },
                post: {
                    summary: 'Create a new test project',
                    requestBody: {
                        required: true,
                        content: {
                            'application/json' => {
                                schema: { '$ref' => '#/components/schemas/TestProjectsInput' }
                            }
                        }
                    },
                    responses: {
                        '201' => {
                            description: 'Created test project',
                            content: {
                                'application/json' => {
                                    schema: { '$ref' => '#/components/schemas/TestProjects' }
                                }
                            }
                        }
                    }
                }
            },
            '/api/test/{id}' => {
                get: {
                    summary: 'Get test project by ID',
                    parameters: [
                        {
                            name: 'id',
                            'in' => 'path',
                            required: true,
                            schema: { type: 'integer' }
                        }
                    ],
                    responses: {
                        '200' => {
                            description: 'Test project found',
                            content: {
                                'application/json' => {
                                    schema: { '$ref' => '#/components/schemas/TestProjects' }
                                }
                            }
                        },
                        '404' => { description: 'Project not found' }
                    }
                },
                put: {
                    summary: 'Update test project',
                    parameters: [
                        {
                            name: 'id',
                            'in' => 'path',
                            required: true,
                            schema: { type: 'integer' }
                        }
                    ],
                    requestBody: {
                        required: true,
                        content: {
                            'application/json' => {
                                schema: { '$ref' => '#/components/schemas/TestProjectsInput' }
                            }
                        }
                    },
                    responses: {
                        '200' => { description: 'Updated test project' },
                        '404' => { description: 'Project not found' }
                    }
                },
                delete: {
                    summary: 'Delete test project',
                    parameters: [
                        {
                            name: 'id',
                            'in' => 'path',
                            required: true,
                            schema: { type: 'integer' }
                        }
                    ],
                    responses: {
                        '200' => { description: 'Deleted successfully' },
                        '404' => { description: 'Project not found' }
                    }
                }
            }
        },
        components: {
            schemas: {
                TestProjects: {
                    type: 'object',
                    properties: {
                        Id: { type: 'integer' },
                        Name: { type: 'string' }
                    }
                },
                TestProjectsInput: {
                    type: 'object',
                    required: ['Name'],
                    properties: {
                        Name: { type: 'string' }
                    }
                }
            }
        }
    }.to_json
end

# GET /api/test - Get all projects
get '/api/test' do
    content_type :json
    db = get_db
    begin
        controller = TestController.new(db)
        controller.get_all.to_json
    rescue => e
        # Re-raise to trigger Sinatra error handler
        raise e
    ensure
        db&.close
    end
end

get '/api/test/' do
    content_type :json
    db = get_db
    begin
        controller = TestController.new(db)
        controller.get_all.to_json
    ensure
        db&.close
    end
    # Do NOT catch generic Exception - let it bubble up to Sinatra error handler
end

# GET /api/test/:id - Get project by ID
get '/api/test/:id' do
    content_type :json
    db = get_db
    begin
        controller = TestController.new(db)
        result = controller.get_by_id(params['id'].to_i)
        
        if result.nil?
            status 404
            { error: 'Project not found' }.to_json
        else
            result.to_json
        end
    ensure
        db&.close
    end
    # Do NOT catch generic Exception - let it bubble up to Sinatra error handler
end

# POST /api/test - Create project
post '/api/test' do
    content_type :json
    db = get_db
    begin
        controller = TestController.new(db)
        data = parse_json_body
        result = controller.create(data)
        status 201
        result.to_json
    ensure
        db&.close
    end
    # Do NOT catch generic Exception - let it bubble up to Sinatra error handler
end

post '/api/test/' do
    content_type :json
    db = get_db
    begin
        controller = TestController.new(db)
        data = parse_json_body
        result = controller.create(data)
        status 201
        result.to_json
    ensure
        db&.close
    end
    # Do NOT catch generic Exception - let it bubble up to Sinatra error handler
end

# PUT /api/test/:id - Update project
put '/api/test/:id' do
    content_type :json
    db = get_db
    begin
        controller = TestController.new(db)
        data = parse_json_body
        result = controller.update(params['id'].to_i, data)
        
        if result.nil?
            status 404
            { error: 'Project not found' }.to_json
        else
            result.to_json
        end
    ensure
        db&.close
    end
    # Do NOT catch generic Exception - let it bubble up to Sinatra error handler
end

# DELETE /api/test/:id - Delete project
delete '/api/test/:id' do
    content_type :json
    db = get_db
    begin
        controller = TestController.new(db)
        
        if controller.delete(params['id'].to_i)
            { message: 'Deleted successfully' }.to_json
        else
            status 404
            { error: 'Project not found' }.to_json
        end
    ensure
        db&.close
    end
    # Do NOT catch generic Exception - let it bubble up to Sinatra error handler
end

# Startup error handler - catch errors during require or initialization
at_exit do
    if $!
        exception = $!
        logger.error("[STARTUP ERROR] Application failed to start: #{exception.message}")
        logger.error(exception.backtrace.join("\n")) if exception.backtrace
        
        # Send startup error to endpoint (fire and forget)
        runtime_error_endpoint_url = ENV['RUNTIME_ERROR_ENDPOINT_URL']
        board_id = ENV['BOARD_ID']
        
        if runtime_error_endpoint_url && !runtime_error_endpoint_url.empty?
            Thread.new do
                begin
                    require 'net/http'
                    require 'uri'
                    require 'json'
                    
                    stack_trace = exception.backtrace ? exception.backtrace.join("\n") : 'N/A'
                    first_line = exception.backtrace ? exception.backtrace.first : nil
                    file_name = nil
                    line_number = nil
                    if first_line && (match = first_line.match(/(.+):(\d+):/))
                        file_name = match[1]
                        line_number = match[2].to_i
                    end
                    
                    payload = {
                        boardId: board_id,
                        timestamp: Time.now.utc.iso8601,
                        file: file_name,
                        line: line_number,
                        stackTrace: stack_trace,
                        message: exception.message || 'Unknown error',
                        exceptionType: exception.class.name,
                        requestPath: 'STARTUP',
                        requestMethod: 'STARTUP',
                        userAgent: 'STARTUP_ERROR'
                    }.to_json
                    
                    uri = URI(runtime_error_endpoint_url)
                    http = Net::HTTP.new(uri.host, uri.port)
                    http.use_ssl = (uri.scheme == 'https')
                    http.open_timeout = 5
                    http.read_timeout = 5
                    
                    request_obj = Net::HTTP::Post.new(uri.path)
                    request_obj['Content-Type'] = 'application/json'
                    request_obj.body = payload
                    
                    http.request(request_obj)
                rescue => e
                    # Ignore
                end
            end
        end
    end
end
