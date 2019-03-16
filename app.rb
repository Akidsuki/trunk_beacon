require 'sinatra'
require 'mysql2'
require 'line/bot'

class App < Sinatra::Base
  def client
    @client ||= Line::Bot::Client.new { |config|
      # TODO 環境変数化する
      config.channel_secret = "7251b6d94ddd87db824fc02275042c12"
      config.channel_token = "t3pWIjQC1Hj3u6IFxIW0ocUHmoUafFP9hGUYP0ksNBQPW4zrnkccjCb95+CYiicD7ZUjjsovWoi0KbLt/aZ8JeqvlbKMGbN2auCZJ2JnVvL7QowXCMcWuGT3uUknz0vTVG+5Br0KR7Kq5AD22l0nrQdB04t89/1O/w1cDnyilFU="
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

  post '/callback' do
    body = request.body.read

    signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client.validate_signature(body, signature)
      error 400 do 'Bad Request' end
    end

    events = client.parse_events_from(body)
    events.each { |event|
      case event
      when Line::Bot::Event::Follow
        follow_event(event)
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Image
          content = client.get_message_content(event.message['id'])
          tf = File.open("./static/#{event.message['id']}.jpg", 'wb')
          tf.write(content.body)

          line_id = event['source']['userId']
          image_name = "#{event.message['id']}.jpg"

          create_tero(line_id, image_name)

          # TODO 該当するユーザーにテロする

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

  def create_user(line_id)
    res = client.get_profile(line_id)
    nickname = res.body['displayName']
    statement = db.prepare('INSERT INTO Users (LINEID, nickname, created_at) VALUES(?, ? ,NOW())')
    statement.execute(line_id, nickname)
    statement.close
  end

  def create_tero(line_id, image_name)
    statement = db.prepare('INSERT INTO Teros (user_id, img_name, created_at) VALUES(?, ? ,NOW())')
    statement.execute(line_id, image_name)
    statement.close
  end

  def db
    return @db_client if @db_client

    # 環境変数化する
    @db_client = Mysql2::Client.new(
      host: 'public.2it8h.tyo1.database-hosting.conoha.io',
      port: 3306,
      username: '2it8h_developer',
      password: 'Line123456789',
      database: '2it8h_development',
    )

    @db_client
  end
end
