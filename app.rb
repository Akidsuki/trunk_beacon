require 'sinatra'
require 'mysql2'
require 'line/bot'

class App < Sinatra::Base
  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_secret = "7251b6d94ddd87db824fc02275042c12"
      config.channel_token = "t3pWIjQC1Hj3u6IFxIW0ocUHmoUafFP9hGUYP0ksNBQPW4zrnkccjCb95+CYiicD7ZUjjsovWoi0KbLt/aZ8JeqvlbKMGbN2auCZJ2JnVvL7QowXCMcWuGT3uUknz0vTVG+5Br0KR7Kq5AD22l0nrQdB04t89/1O/w1cDnyilFU="
    }
  end

  get '/' do
    "サーバー動いてるお！"
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
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Text
          message = {
            type: 'text',
            text: event.message['text']
          }
          client.reply_message(event['replyToken'], message)
        when Line::Bot::Event::MessageType::Image, Line::Bot::Event::MessageType::Video
          response = client.get_message_content(event.message['id'])
          tf = Tempfile.open("content")
          tf.write(response.body)
        end
      end
    }

    "OK"
  end

  def db
    return @db_client if @db_client

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
