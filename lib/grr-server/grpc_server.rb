require 'timeout'

module Grr
  # Grpc service implementation
  class GrpcServer < Grr::RestService::Service

    attr_reader :app, :logger

    def initialize(app, logger)
      @app = app
      @logger = logger
    end

    # do_request implements the DoRequest rpc method.
    def do_request(rest_req, _call)

      logger.info("Grpc-Rest requested received. Location: #{rest_req.location};")

      # Duplicate is needed, because rest_req['body'] is frozen.
      bodyDup = rest_req['body'].dup
      bodyDup.force_encoding("ASCII-8BIT") # Rack rquires this encoding
      qsDup = rest_req['queryString'].dup
      qsDup.force_encoding("ASCII-8BIT")

      # Create rack env for the request
      env = new_env(rest_req['method'],rest_req['location'],qsDup,bodyDup)

      # Execute the app's .call() method (Rack standard)
      # blocks execution, sync call
      status = Timeout::timeout(5) {
        status, headers, body = app.call(env)
      }
      # logger.info("Status is: #{status}");
      # logger.info("Headers are: #{headers.to_s}");

      # Parse the body (may be chunked)
      bodyString = reassemble_chunks(body)
      File.write('./out.html',bodyString) # For debugging. Errors are returned in html sometimes, hard to read on the command line.

      logger.info('Got response.');
      # Create new Response Object
      Grr::RestResponse.new(headers: headers.to_s, status: status, body: bodyString)
    end

    # Rack needs ad ENV to process the request
    # see http://www.rubydoc.info/github/rack/rack/file/SPEC
    def new_env(method, location, queryString, body)
      {
        'REMOTE_ADDR'      => '::1',
        'REQUEST_METHOD'   => method,
        'HTTP_ACCEPT'      => 'application/json',
        'CONTENT_TYPE'     => 'application/json',
        'SCRIPT_NAME'      => '',
        'PATH_INFO'        => location,
        'REQUEST_PATH'     => location,
        'REQUEST_URI'      => location,
        'QUERY_STRING'     => queryString,
        'CONTENT_LENGTH'   => body.bytesize.to_s,
        'SERVER_NAME'      => 'localhost',
        'SERVER_PORT'      => '6575',
        'HTTP_HOST'        => 'localhost:6575',
        'HTTP_USER_AGENT'  => 'grr/0.1.0',
        'SERVER_PROTOCOL'  => 'HTTP/1.1',
        'HTTP_VERSION'     => 'HTTP/1.1',
        'rack.version'     => Rack.version.split('.'),
        'rack.url_scheme'  => 'http',
        'rack.input'       => StringIO.new(body),
        'rack.errors'      => StringIO.new(''),
        'rack.multithread' => false,
        'rack.run_once'    => false,
        'rack.multiprocess'=> false,
      }
    end

    def reassemble_chunks raw_data
      reassembled_data = ""
      position = 0
      raw_data.each do |chunk|
        end_of_chunk_size = chunk.index "\r\n"
        if end_of_chunk_size.nil?
          logger.info("no chunk found")
          reassembled_data = chunk
          break
        end
        chunk_size = chunk[0..(end_of_chunk_size-1)].to_i 16 # chunk size represented in hex
        # TODO ensure next two characters are "\r\n"
        position = end_of_chunk_size + 2
        end_of_content = position + chunk_size
        str = chunk[position..end_of_content-1]
        reassembled_data << str
        # TODO ensure next two characters are "\r\n"
      end
      reassembled_data
    end

  end
end
