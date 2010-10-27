require 'rubygems'
require 'sinatra'
require 'erb'
require 'cassandra'
require 'lib/to_slug'
require 'time'
require 'yaml'
require 'simple_uuid'
require 'maruku'
require 'sanitize'

# Load config file
config = begin
  YAML::load( File.open('config.yml') )
rescue
  {}
end

db = Cassandra.new('sinandra')

before do
  @tags = db.get(:Lists, 'tags').keys
  @blog_name = config['title'] || 'a simple blog'
  @blog_author = config['author'] || 'Barack Obama'
  @blog_about = config['about'] || "Lorem Ipsum is simply dummy text of the printing typesetting industry. Lorem Ipsum has been the industrys standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book."
  @blog_username = config['username'] || 'admin'
  @blog_password = config['password'] || 'super'
end

get '/' do
  @posts = db.get(:TaggedPosts, '__notag__', :reversed => true).map {|time,id| db.get(:BlogEntries, id) }
  erb :index
end

get '/archive' do
  @archives = []
  db.get(:Lists, 'archives').sort_by { |id, time| Time.parse(time) }.map {|id,time| id }.each do |month|
    posts = db.get(:Archives, month, :reversed => true).map {|time,id| db.get(:BlogEntries, id) }
    @archives << { month => posts }
  end
  erb :archive
end

get '/tag/:name' do
  @posts = db.get(:TaggedPosts, params[:name], :reversed => true).map {|time,id| db.get(:BlogEntries, id) }
  erb :index
end

get '/posts/new' do
  protected!
  erb :new_post
end

get '/posts/:post' do
  @post = db.get(:BlogEntries, params[:post])
  @comments = db.get(:Comments, params[:post]).map {|key, comments| comments }
  erb :show
end

get '/feed' do
  "Return rss feed of posts"
end

post '/posts/create' do
  protected!
  post_body = Sanitize.clean(params['post']['body'], Sanitize::Config::BASIC)
  @post = {'title' => params['post']['title'], 
           'body' => post_body,
           'tags' => params['post']['tags'],
           'slug' => params['post']['title'].to_slug,
           'author' => @blog_author}
  archive_key = Date::MONTHNAMES[Time.now.month] + ' ' + Time.now.year.to_s
  db.insert(:BlogEntries, @post['title'].to_slug, @post)
  db.insert(:TaggedPosts, '__notag__', {SimpleUUID::UUID.new => @post['title'].to_slug})
  db.insert(:Lists, 'archives', { archive_key => Time.now.to_s })
  db.insert(:Archives, archive_key, {SimpleUUID::UUID.new => @post['title'].to_slug})
  @post['tags'].split(',').map {|t| t.strip }.each do |tag|
    db.insert(:TaggedPosts, tag, {SimpleUUID::UUID.new => @post['title'].to_slug})
    db.insert(:Lists, 'tags', {tag => Time.now.to_s})
  end
  redirect "/posts/#{@post['title'].to_slug}"
end

post '/comments/create/:post' do
  comment_body = Sanitize.clean(params['comment'], Sanitize::Config::BASIC)
  @comment = { 'commenter' => params['commenter'],
               'email' => params['email'],
               'body' => comment_body,
               'posted_on' => Time.now.strftime("%B %d, %Y"),
               'posted_at' => Time.now.strftime("%H:%M")}
  db.insert(:Comments, params[:post], {SimpleUUID::UUID.new => @comment})
  redirect "/posts/#{params[:post]}"
end

get '/*' do
  erb :not_found
end

helpers do
  include Rack::Utils
  alias_method :h, :escape_html

  def protected!
    unless authorized?
      response['WWW-Authenticate'] = %(Basic realm="Testing HTTP Auth")
      throw(:halt, [401, "Not authorized\n"])
    end
  end

  def authorized?
    @auth ||=  Rack::Auth::Basic::Request.new(request.env)
    @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == [@blog_username, @blog_password]
  end

end


__END__

@@ layout
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
  <head>
    <meta http-equiv="Content-Type" content="text/html;charset=utf-8" />
    <title><%= @blog_name %></title>
    <link type="text/css" href="/styles.css" media="screen" rel="stylesheet"/>
  </head>
  <body>
    <div id="header">
      <div id="administration">
        <a href="/posts/new">Create a post</a>
      </div>
      <h1><%=h @blog_name %></h1>
      <ul>
        <li><a href="/">Home</a></li>
        <li><a href="/archive">Archive</a></li>
      </ul>
    </div>
    
    <div id="sidebar">
      <h2>About</h2>
      <p>
        <%=h @blog_about %>
      </p>
      <h2>Tags</h2>
      <ul>
      <% @tags.map {|t| t.strip}.each do |tag| %>
        <li><a href="/tag/<%=h tag %>"><%=h tag %></a></li>
      <% end %>
      </ul>
    </div>
    
    <div id="main">
     <%= yield %>
    </div>
    <div class="break"></div>
    
    <div id="footer">
      Copyright &copy; Intellum
    </div>
  
  </body>
</html>

@@ index
<% @posts.each do |post| %>
<div class="post">
	<h2><a href="/posts/<%=h post["slug"] %>"><%=h post["title"] %></a></h2>
	<p>
		by <%=h post["author"] %>
	</p>
	<p>
		<%= Maruku.new(post["body"]).to_html %>
	</p>
	<div class="tags"><strong>Tags:</strong>
	  <% post["tags"].split(',').map {|t| t.strip }.each do |tag| %>
	    <a href="/tag/<%=h tag %>"><%=h tag %></a>&nbsp;
	  <% end %>
	</div>
</div>
<% end %>

@@ new_post
<h2>New blog post:</h2>
<form action="/posts/create" method="POST">
  <p>
    <label for="post_title">Title</label><br/>
    <input id="post_title" name="post[title]" />
  </p>
  <p>
    <label for="post_body">Body</label><br/>
    <textarea id="post_body" name="post[body]" style="height: 500px"></textarea><br/>
    <small>Use <a target="_new" href="http://en.wikipedia.org/wiki/Markdown">Markdown</a> for formatting.</small><br/>
  </p>  
  <p>
    <label for="post_tags">Tags <em>(comma separated)</em></label><br/>
    <input id="post_tags" name="post[tags]" />
  </p>
  <p>
    <button type="submit">Save</button>
  </p>
</form>
<script>
  document.getElementById('post_title').focus();
</script>

@@ show
<div class="post">
<h2><%=h @post["title"] %></h2>
<p>
	by <%=h @post["author"] %>
</p>
<p>
	<%= Maruku.new(@post["body"]).to_html %>
</p>
<div class="tags"><strong>Tags: </strong>
  <% @post["tags"].split(',').map {|t| t.strip }.each do |tag| %>
    <a href="/tag/<%=h tag %>"><%=h tag %></a>&nbsp;
  <% end %>
</div>
</div>

<div id="comments">
  <h3>Comments</h3>
  <% if @comments.size == 0 %>
    <p><em>No comments. Be the first to post one below</em></p>
  <% end %>
  <% @comments.each do |comment| %>
    <div class="comment">
      <div class="comment_headline">
        <em>Posted by </em><strong><%=h comment['commenter'] %></strong><em>
        on <%=h comment['posted_on'] %>
        at <%=h comment['posted_at'] %></em>
      </div>
      <p>
        <%= Maruku.new(comment['body']).to_html %>
      </p>
    </div>
  <% end %>

	<form action="/comments/create/<%=h @post['slug'] %>" method="POST">
		<p>
		  <label for="commenter">Name:</label><br/>
		  <input id="commenter" name="commenter" />
		</p>
		<p>
		  <label for="email">Email:</label><br/>
		  <input id="email" name="email" />
		</p>  
		<p>
		  <label for="comment">Comment</label><br/>
		  <textarea id="comment" name="comment"></textarea><br/>
      <small>Use <a target="_new" href="http://en.wikipedia.org/wiki/Markdown">Markdown</a> for formatting.</small><br/>		  
		</p>
		<p>
		  <button type="submit">Submit Comment</button>
		</p>
	</form>
	
</div>

@@ archive
<% @archives.each do |month| %>
  <div id="archive">
  <h3><%=h month.keys[0] %></h3>
  <ul>
  <% month.values[0].each do |post| %>
    <li><a href='/posts/<%=h post["slug"] %>'><%=h post['title'] %></a></li>
  <% end %>
  </ul>
  </div>
<% end %>

@@ not_found
<h2>Page Not Found</h2>
