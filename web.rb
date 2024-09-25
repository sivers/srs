require 'sinatra'
require 'pg'
require 'json'

class DBAPI
  def initialize
    @db = PG::Connection.new(dbname: 'srs', user: 'srs')
  end
  def a(func, *params)
    qs = '(%s)' % (1..params.size).map {|i| "$#{i}"}.join(',')
    sql = "select ok, js from #{func}#{qs}"
    r = @db.exec_params(sql, params)[0]
    [
      (r['ok'] == 't'),
      JSON.parse(r['js'], symbolize_names: true)
    ]
  end
end
API = DBAPI.new

# TODO
get '/' do
  erb :home
end

