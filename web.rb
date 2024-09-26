require 'sinatra'
require 'pg'
require 'json'

# SQL query-builder:
# a('decks') = "select ok, js from srs.decks()"
# a('review', 9, 'good') = "select ok, js from srs.review($1,$2)", [9, 'good']
# returns boolean ok, and parsed JSON
class DBAPI
  def initialize
    @db = PG::Connection.new(dbname: 'srs', user: 'srs')
  end
  def a(func, *params)
    qs = '(%s)' % (1..params.size).map {|i| "$#{i}"}.join(',')
    sql = "select ok, js from srs.#{func}#{qs}"
    r = @db.exec_params(sql, params)[0]
    [
      (r['ok'] == 't'),
      JSON.parse(r['js'], symbolize_names: true)
    ]
  end
end
API = DBAPI.new

get '/' do
  ok, @decks = API.a('decks')
  erb :home
end

post '/' do
  API.a('add', params[:deck], params[:front], params[:back])
  redirect to('/')
end

get '/next' do
  ok, @card = API.a('next', String(params[:deck]))
  redirect to('/') unless ok
  erb :card
end

post '/card/:id/edit' do
  API.a('edit', params[:id], params[:deck], params[:front], params[:back])
  redirect to('/next?deck=%s' % params[:deck])
end

post '/card/:id/review' do
  ok, c = API.a('review', params[:id], params[:rating])
  redirect to('/next?deck=%s' % c[:deck])
end

# HTML escape
def h(text)
  esc = {
    '&' => '&amp;',
    '<' => '&lt;',
    '>' => '&gt;',
    '"' => '&quot;'}
  pat = Regexp.union(*esc.keys)
  text.to_s.gsub(pat) {|c| esc[c] }
end

