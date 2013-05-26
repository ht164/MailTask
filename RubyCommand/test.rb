require "time"
require "mongo"
include Mongo

class Main
  def initialize()
    @cl = MongoClient.new("localhost", 27017)
    @db = @cl.db("mydb")
    @ml = @db.collection("mail")
  end
  
  def run(dir)
    # *.wemファイルを再帰的に検索
    if (dir.nil?)
      dir = ""
    end
    Dir.glob(dir + "/**/*.wem").each{|f|
      read(f)
    }
  end
  
  def read(filename)
    to = ""
    from = ""
    cc = ""
    id = ""
    date = ""
    ref = ""
    contents = ""
    # ファイル読み込み
    open(filename) { |file|
      mode = 1 # 現在の読み込みモード: 1...通常ヘッダ、2...text/plainのテキスト
               # 3...boundaryありのヘッダ、4...boundaryありのテキスト
               # 5...boundaryありのoctet-stream
               # 6...次のboundaryまで飛ばす
      contentType = 1 # content-type: 1...text/plain, 2...multipart/mixed
      boundary = ""
      # 1行ずつ読む
      while l = file.gets
        case mode
        when 1
          if (l == "\r\n")
            # もう1回改行が発生するので、とりあえず読んどく
            l = file.gets
            mode = 2
            next
          end
          # key: value の形
          kv = l.split(/\s*:\s*/)
          case kv[0].downcase
          when "to"
            to = kv[1].strip
          when "from"
            from = kv[1].strip
          when "cc"
            cc = kv[1].strip
          when "message-id"
            id = kv[1].strip
          when "date"
            # 値の部分は":"で連結する
            newv = kv[1..(kv.size - 1)]
            date = Time.parse(newv.join(":").strip)
          when "in-reply-to"
            ref = kv[1].strip
          when "references"
            ref = kv[1].strip
          when "content-type"
            # 最後の文字は「;」か?
            if (kv[1].strip[-1,1] == ";")
              # もう1行読む
              l = file.gets
              kv = l.split(/=/)
              if (kv[0].strip == "boundary")
                # クォート文字は除く
                boundary = kv[1].strip.sub(/\A['"]/,"").sub(/['"]\z/,"")
              end
            end
          end
        when 2
          # text or boundary?
          if (l.strip == "--" + boundary)
            # boundary
            mode = 3
            next
          end
          contents += l
        when 3
          # boundaryありのヘッダ
          if l == "\r\n"
            # コンテンツ
            mode = 4
            next
          end
          # key: value の形
          kv = l.split(/\s*:\s*/)
          if (kv[0] == "Content-Type")
            # content-type
            if (kv[1].index("text/plain") == nil)
              # text/plainではないので飛ばす
              mode = 6
            end
          end
        when 4
          # boundaryありのコンテンツ
          if (l.strip == "--" + boundary)
            # boundary
            mode = 3
            next
          end
          contents += l
        when 6
          # 飛ばす
          if (l.strip == "--" + boundary)
            mode = 3
          end
        end
      end
    }
    
    # 格納
    storeMail(id, to, from, cc, date, ref, contents)
  end
  
  def storeMail(id, to, from, cc, date, ref, contents)
    # MongoDBに格納
    obj = {"id" => id, "to" => to, "from" => from, "cc" => cc, "date" => date, "ref" => ref, "contents" => contents}
    @ml.save(obj)
    # 確認
    @ml.find_one
  end
end

m = Main.new()
m.run(ARGV[0])
