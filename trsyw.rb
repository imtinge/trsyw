require 'open-uri'
require 'nokogiri'
require 'sqlite3'

def get_pages
  pages = Queue.new
	pages << "http://www.trs.gov.cn/xwzx/trsyw/index.html"

  html = Nokogiri::HTML(open("http://www.trs.gov.cn/xwzx/trsyw/index.html"))
  last_page_number = html.css(".page").text.scan(/\d+/).first.to_i - 1

	(1..last_page_number).each do |i|
		pages << "http://www.trs.gov.cn/xwzx/trsyw/index_#{i}.html"
	end
	pages
end

def get_post_links(db, page)
	links = []

  html = Nokogiri::HTML(open(page))

  links = html.css("ul.text-list>li>a").map { |a| a['href'] }
  irregular_links = links.reject { |link| link.include?('trsyw') }

  irregular_links.each do |post|
    db.execute("INSERT INTO irregular_posts (page_link, post_link) VALUES (?, ?)", page, post)
  end

  links - irregular_links
end

def get_post_data(db, post)
  site_id = 199
  pubdate, count_id = post.scan(/t(\d{8}_\d+)\./).first.first.split('_')

  count_link = "http://www.trs.gov.cn/count/index?id=#{count_id}&siteid=#{site_id}"
  begin
    html = Nokogiri::HTML(open(count_link, 'User-Agent' => 'ruby'))
    hits = html.text.scan(/\d+/).first
  rescue => e
    puts "#{count_link}, #{e.message}"
    hits = rand(256)
  end

  html = Nokogiri::HTML(open(post))
  title = html.css("div.title>h1").map { |t| t.text }.join
  content = html.css("font#Zoom").text.strip

  db.execute("INSERT INTO posts (title, pubdate, hits, content) VALUES (?, ?, ?, ?)", title, pubdate, hits, content)
end


db = SQLite3::Database.open 'trsyw.db'
db.execute <<-SQL
  DROP TABLE IF EXISTS posts;
SQL
db.execute <<-SQL
  DROP TABLE IF EXISTS irregular_posts;
SQL

db.execute <<-SQL
  CREATE TABLE posts (
    title text,
    hits int,
    pubdate char(8),
    content blob
  );
SQL

db.execute <<-SQL
  CREATE TABLE irregular_posts (
    page_link char(128),
    post_link varchar(256)
  );
SQL

pages = get_pages
page_threads = []

posts = Queue.new
50.times do |i|
  page_threads << Thread.new do
    begin
      while page = pages.pop(true)
        get_post_links(db, page).each do |link|
          posts << link
        end
      end
    rescue ThreadError
    end
  end
end

page_threads.each { |t| t.join }
pages.close

threads = []
20.times do |i|
  threads << Thread.new do
    begin
      while post = posts.pop(true)
        sleep 10
        get_post_data(db, post)
      end
    rescue ThreadError
    end
  end
end

threads.each { |t| t.join }

posts.close
