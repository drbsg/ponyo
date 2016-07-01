structure Ponyo_Encoding_Json =
struct
    local
        structure String = Ponyo_String_
        structure Format = Ponyo_Format
        structure Char = Ponyo_Char_
    in

    structure Token =
    struct
        datatype t =
            String of string
          | Int of int
          | Real of real
          | True
          | False
          | Symbol of string

        val LCBracket = "{"
        val RCBracket = "}"
        val LBracket = "["
        val RBracket = "]"
        val Comma = ","
        val Colon = ":"
    end

    datatype t =
        String of string
      | Int of int
      | Real of real
      | True
      | False
      | List of t list
      | Object of (string * t) list

    exception MalformedString of char list
    exception MalformedNumber of char list
    exception MalformedTrue
    exception MalformedFalse
    exception MalformedJson of Token.t list * string
    exception MalformedKey of Token.t list
    exception MalformedList of Token.t list

    fun lex (json: char list, l: Token.t list) : Token.t list =
        case json of
            [] => List.rev (l)
          | #"{" :: rest => lex (rest, Token.Symbol Token.LCBracket :: l)
          | #"}" :: rest => lex (rest, Token.Symbol Token.RCBracket :: l)
          | #":" :: rest => lex (rest, Token.Symbol Token.Colon :: l)
          | #"[" :: rest => lex (rest, Token.Symbol Token.LBracket :: l)
          | #"]" :: rest => lex (rest, Token.Symbol Token.RBracket :: l)
          | #"," :: rest => lex (rest, Token.Symbol Token.Comma :: l)
          | #"\"" :: rest => lexString (#"\"", rest, l)
          | #"'" :: rest => lexString (#"'", rest, l)
          | #"t" :: rest => lexTrue (rest, l)
          | #"f" :: rest => lexFalse (rest, l)
          | #" " :: rest => lex (rest, l)
          | #"\r" :: rest => lex (rest, l)
          | #"\t" :: rest => lex (rest, l)
          | #"\n" :: rest => lex (rest, l)
          | _ => lexNumber (json, l)

    and lexString (starter: char, json: char list, l: Token.t list) : Token.t list =
        case json of
            [] => raise MalformedString []
          | _ =>
        let
            fun lexStringHelper (s: char list, accum: char list) : char list * char list =
                case s of
                    [] => raise MalformedString (accum) (* json string ended without closing a string *)
                  | first :: rest =>
                if first = starter
                    then (List.rev accum, rest)
                else if rest = []
                    then raise MalformedString (accum) (* json string ended without closing a string *)
                else if first = #"\\" andalso Char.List.contains ([#"'", #"\""], List.hd rest) (* TODO: \\ *)
                    then lexStringHelper (List.tl rest, List.hd rest :: accum)
                else lexStringHelper (rest, first :: accum)

            val (string, rest) = lexStringHelper (json, [])
            val t = Token.String (String.implode string)
        in
            lex (rest, t :: l)
        end

    and lexNumber (json: char list, l: Token.t list) : Token.t list =
        case json of
            [] => raise MalformedNumber []
          | _ =>
        let
            fun lexNumberHelper (n: char list, accum: char list) : char list * char list =
                case n of
                    [] => (List.rev accum, [])
                  | first :: rest =>
                if Char.List.contains (String.explode("0123456789.-"), first)
                    then lexNumberHelper (rest, first :: accum)
                else (List.rev accum, first :: rest)
            val (n, rest) = lexNumberHelper (json, [])
        
            val t =
                case Int.fromString (String.implode n) of
                    SOME i => Token.Int (i)
                  | _ =>
                case Real.fromString (String.implode n) of
                    SOME r => Token.Real (r)
                  | _ => raise MalformedNumber (n)
        in
            lex (rest, t :: l)
        end

    and lexTrue (json: char list, l: Token.t list) : Token.t list =
        case json of
            #"r" :: (#"u" :: (#"e" :: rest)) => lex (rest, Token.True :: l)
          | _ => raise MalformedTrue

    and lexFalse (json: char list, l: Token.t list) : Token.t list =
        case json of
            #"a" :: (#"l" :: (#"s" :: (#"e" :: rest))) => lex (rest, Token.False :: l)
          | _ => raise MalformedFalse

    infix >>=
    fun a >>= b =
        b (a)

    fun parse (json: string) : t =
        case lex (String.explode json, []) of
            [] => raise MalformedJson ([], "Lexing error")
          | tokens =>
        case parseJson (tokens) of
            (t, _) => t

    and parseJson (json: Token.t list) : t * Token.t list =
        case json of
            Token.Real r :: rest => (Real r, rest)
          | Token.Int r :: rest => (Int r, rest)
          | Token.String s :: rest => (String s, rest)
          | Token.True :: rest => (True, rest)
          | Token.False :: rest => (False, rest)
          | Token.Symbol s :: rest =>
          (if s = Token.LCBracket
              then parseObject (rest)
          else if s = Token.LCBracket then parseList (rest) else raise MalformedJson (json, "Expected ending bracket"))
          | _ => raise MalformedJson (json, "Expected json value")

    and parseSymbol (json: Token.t list, s: string) : Token.t list =
        case json of
            Token.Symbol first :: rest => if first = s then rest else []
          | _ => raise MalformedJson (json, "Expected symbol " ^ s)

    and parseString (json: Token.t list) : string * Token.t list =
        case json of
            Token.String first :: rest => (first, rest)
          | _ => raise MalformedKey (json)

    and parseList (json: Token.t list): t * Token.t list =
        parseListElements (json, []) >>= (fn (elements, json) =>
        case parseSymbol (json, Token.RBracket) of
            [] => raise MalformedList (json)
          | json => (List elements, json))

    and parseListElements (json: Token.t list, elements: t list) : t list * Token.t list =
        parseJson (json) >>= (fn (e, json) =>
        case parseSymbol (json, Token.Comma) of
            [] => (List.rev (e :: elements), json)
          | json => parseListElements (json, e :: elements))

    and parseObject (json: Token.t list) : t * Token.t list =
        parsePairs (json, []) >>= (fn (pairs, json) =>
        case parseSymbol (json, Token.RCBracket) of
            [] => (Object (pairs), json)
          | json => (Object (pairs), json))

    and parsePairs (json: Token.t list, pairs: (string * t) list) : (string * t) list * Token.t list =
        parsePair (json) >>= (fn (pair, json) =>
        case parseSymbol (json, Token.Comma) of
            [] => (List.rev (pair :: pairs), json)
          | json => parsePairs (json, pair :: pairs))

    and parsePair (json: Token.t list) : (string * t) * Token.t list =
        parseString (json) >>= (fn (string, json) =>
        case parseSymbol (json, Token.Colon) of
            [] => raise MalformedJson (json, "Expected symbol " ^ Token.Colon)
          | json =>
        parseJson (json) >>= (fn (t, json) =>
        ((string, t), json)))

    structure Marshall =
    struct
        fun marshall (object: t, key: string) : (t * t) =
            case object of
                Object (pairs) =>
                  let
                      fun findKey (pairs, key) =
                          case pairs of
                              (someKey, someVal) :: pairs => if someKey = key then SOME (someVal) else findKey (pairs, key)
                            | [] => NONE
                  in
                      case findKey (pairs, key) of
                          SOME v => (object, v)
                        | _ => raise Fail "Key not found"
                  end
              | _ => raise Fail "Cannot marshall non-object"

        fun marshallString (object: t, key: string) : (t * string) option =
            case marshall (object, key) of
                (object, String v) => SOME (object, v)
              | _ => NONE

        fun marshallInt (object: t, key: string) : (t * int) option =
            case marshall (object, key) of
                (object, Int v) => SOME (object, v)
              | _ => NONE

        fun marshallBool (object: t, key: string) : (t * bool) option =
            case marshall (object, key) of
                (object, True) => SOME (object, true)
              | (object, False) => SOME (object, false)
              | _ => NONE

        fun marshallReal (object: t, key: string) : (t * real) option =
            case marshall (object, key) of
                (object, Real r) => SOME (object, r)
              | _ => NONE

        fun a >>= b =
            case a of
                SOME v => b (v)
             | _ => raise Fail "Marshalling error"
    end

    end
end
