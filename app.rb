require 'sinatra'
require 'sinatra/cross_origin'
require 'mysql2'
require 'line/bot'
require 'json'
require 'pry'
require 'active_support/all'
require "net/http"

$BASE_URL = 'https://trunk-beacon.herokuapp.com/'

class App < Sinatra::Base
  configure do
    enable :cross_origin
  end

  before do
    response.headers['Access-Control-Allow-Origin'] = '*'
  end

  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
      config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
    }
  end

  get '/' do
    "サーバー動いてるお！"
  end

  get '/static/:filename' do
    image = File.open("./static/#{params[:filename]}", 'rb')
    content_type 'img/jpg'
    image
  end

  get '/profile' do
    statement = db.prepare('SELECT LINEID FROM Users')
    rr = statement.execute().to_a
    prof = Hash.new
    rr.each do |r|
      line_id = r['LINEID']
      response = client.get_profile(line_id)
      content = JSON.parse(response.body)
      prof.store(line_id, content['displayName'])
    end

    prof.to_json
  end

  get '/profile/:user_id' do
    statement = db.prepare('SELECT LINEID FROM Users WHERE id = ?')
    line_id = user_id_to_line_id(params[:user_id])
    if line_id.nil?
      status 404
      return 'Not found'
    end

    response = client.get_profile(line_id)
    content = JSON.parse(response.body)

    content['displayName']
  end

  post '/callback' do
    body = request.body.read

    signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client.validate_signature(body, signature)
      error 400 do 'Bad Request' end
    end

    events = client.parse_events_from(body)
    events.each { |event|
      case event
      when Line::Bot::Event::Beacon
        beacon_event(event)
      when Line::Bot::Event::Follow
        follow_event(event)
      when Line::Bot::Event::Postback
        post_back_event(event)
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Image
          content = client.get_message_content(event.message['id'])
          tf = File.open("./static/#{event.message['id']}.jpg", 'wb')
          tf.write(content.body)

          line_id = event['source']['userId']
          image_name = "#{event.message['id']}.jpg"
          statement = db.prepare("select beacon_id from Targets where LINEID = ? order by created_at desc")
          row = statement.execute(line_id).first
          return if row.nil?
          beacon_id = row['beacon_id']

          create_tero(line_id, image_name)
          row = db.query('SELECT LAST_INSERT_ID() AS last_insert_id').first
          statement.close
          last_insert_id = row['last_insert_id']
          # タイムゾーンの関係で１０時間戻す
          # 本当は一時間で良い
          hour_ago = 10.hours.ago

          statement = db.prepare("select distinct beacon_id, LINEID from Targets where created_at > ? and not LINEID = ? and beacon_id = ?")
          row = statement.execute(hour_ago, line_id, beacon_id).to_a
          return if row.nil?

            response = client.get_profile(line_id)
            content = JSON.parse(response.body)
            display_name = content['displayName']

          row.each do |r|
            user_id = line_id_to_user_id(r['LINEID'])
            break if user_id.nil?

            message = {
              type: 'template',
              altText: 'Buttons alt text',
              template: {
                type: 'buttons',
                thumbnailImageUrl: "#{$BASE_URL}/static/#{image_name}",
                text: "#{display_name}からのテロ攻撃です",
                actions: [
                  { label: 'もっとよこせ！', type: 'postback', data: "tero_id=#{last_insert_id}&user_id=#{user_id}&type=#{1}" },
                  { label: '送ってくんな', type: 'postback', data: "tero_id=#{last_insert_id}&user_id=#{user_id}&type=#{0}" },
                ]
              }
            }

            client.push_message(r['LINEID'], message)
          end

          statement.close

          message = {
            type: "text",
            text: "飯テロしたったで!!\nお主も悪よのう"
          }

          client.reply_message(event['replyToken'], message)
        end
      end
    }

    "OK"
  end

  def follow_event(event)
    line_id = event['source']['userId']
    create_user(line_id)

    message = {
      type: "text",
      text: "友達登録ありがとう!!\nよろぴく！"
    }

    client.push_message(line_id, message)
  end

  def beacon_event(event)
    hwid = event['beacon']['hwid']
    line_id = event['source']['userId']

    statement = db.prepare('INSERT INTO Targets (beacon_id, LINEID, created_at) VALUES(?, ?, NOW())')
    statement.execute(hwid, line_id)
    statement.close
  end

  def post_back_event(event)
    uri = "https://trunk-hackathon.herokuapp.com/insert_feedback.php?#{event['postback']['data']}"
    res = Net::HTTP.get_response(URI.parse(uri))

    if res.code == '200'
      user_id = event['postback']['data'].split('=')[2].split('&').first
      line_id = user_id_to_line_id(user_id)
      if line_id.nil?
        status 404
        return 'Not found'
      end

      type = event['postback']['data'].split('=')[3]
      text = type == '0' ? "本当の飯テロを教えてやれ！\nお前もテロするんやで！" : "うまそうな飯やな！\n負けじとお前もテロするんやで！"
      message = {
        type: "text",
        text: text,
      }
      client.push_message(line_id, message)
    end
    p res.body
  end

  def create_user(line_id)
    statement = db.prepare('INSERT INTO Users (LINEID, created_at) VALUES(?, NOW())')
    statement.execute(line_id)
    statement.close
  end

  def create_tero(line_id, image_name)
    user_id = line_id_to_user_id(line_id)

    statement = db.prepare('INSERT INTO Teros (user_id, img_name, created_at) VALUES(?, ? ,NOW())')
    statement.execute(user_id, image_name)
    statement.close
  end

  def user_id_to_line_id(user_id)
    statement = db.prepare('SELECT LINEID FROM Users WHERE id = ?')
    r = statement.execute(user_id).first
    statement.close
    return nil if r.nil?

    r['LINEID']
  end

  def line_id_to_user_id(line_id)
    statement = db.prepare('SELECT id FROM Users WHERE LINEID = ?')
    r = statement.execute(line_id).first

    return nil if r.nil?

    r['id']
  end

  def db
    return @db_client if @db_client

    # TODO 環境変数化する
    @db_client = Mysql2::Client.new(
      host: 'public.2it8h.tyo1.database-hosting.conoha.io',
      port: 3306,
      username: '2it8h_developer',
      password: 'Line123456789',
      database: '2it8h_development',
    )

    @db_client
  end

  def redis
    return @redis_client if @redis_client
    @redis_client = Redis.new(host: "133.130.111.100", port: 6379, password: 'nwE9sH3tt')

    @redis_client
  end
end
