
import CombinedParsers: word, non_word, newline, whitespace_maybe, whitespace_horizontal
import CombinedParsers: Repeat_max

@testset "CombinedParsers" begin
@testset "CharIn" begin
    @test parse(CharIn(isuppercase),"A") =='A'
end

@testset "NamedTuple" begin
    @test parse(Sequence(first = CharIn(isuppercase), second = CharIn(islowercase)),"Ab") == (first='A', second='b')
    @test parse(Sequence(CharIn(isuppercase), :second => CharIn(islowercase)),"Ab") == (second='b',)
end

@testset "Repeat" begin
    @test parse(join(Repeat('a'),","),"a,a") == ['a','a']
end

@testset "parse_all" begin
    @test collect(parse_all(Repeat("a"|"ab"),"aabab")) ==
        [ ["a","a"], ["a","ab","a"], ["a","ab","ab"], ["a","ab"], ["a"],[] ]
end



@testset "Either" begin
    @test parse(Either("a","ab","ac")*AtEnd(),"ab") == ("ab", AtEnd())
    @test_throws ArgumentError parse(Atomic(Either("a","ab","ac"))*AtEnd(),"ab")
end

@testset "Repeat_until" begin
    @test parse(Sequence("(", Repeat_until(!!Either(word,non_word), ")")),
                "(balanced parenthesis)") ==
        ("(",["balanced", " ", "parenthesis"])
    # Test if strings bigger than Repeat_max can be parsed using max optional ArgumentError
    new_Repeat_max = Repeat_max+10;
    dat = 'a'^(new_Repeat_max)*'b';
    @test String(parse(Repeat_until('a','b';max=new_Repeat_max), dat))==dat[1:end-1]
end

@testset "Repeat_stop" begin
    new_Repeat_max = Repeat_max+10;
    dat = 'a'^(new_Repeat_max)*'b';
    @test String(parse(Repeat_stop('a','b';max=new_Repeat_max), dat))==dat[1:end-1]
end

@testset "Bytes" begin
    # simple test for binary parsing
    _iterate(Bytes(1,UInt8),[0x33],1,1,1,nothing)
    @test parse(Bytes(1,UInt8),[0x33]) == 0x33
    @test parse(Bytes(2,UInt16),[0x33,0x66]) == 0x6633
    @test parse(Bytes(4,Float32),[0x55,0x77,0x33,0x66]) == reinterpret(Float32,0x66337755)
end
end

@testset "FlatMap" begin
    @test parse(
        after(with_log("left",Either("a","ab"))) do v
        parser(v)
        end,
        "abab")=="ab"
    # parse(pattern,with_options(Base.PCRE.MULTILINE,"^"))
end
decimal = CharIn(UnicodeClass(:Nd))
decimals = Repeat1(decimal)
@test parse(decimals,"123") == [ "123"... ]

decimal = CharIn('0':'9')
decimals = Repeat1(decimal)
@test parse(decimals,"123") == [ "123"... ]

attribute_parser =
    map(
        (v) -> (lowercase(v[1]) => "$(v[5])")::Pair{String,String},
        Sequence(
            !Repeat1(word), whitespace_maybe,"=", whitespace_maybe,
            Either(Sequence(2,"\"", Repeat_until(AnyChar(),"\"",wrap=JoinSubstring)),
                   Sequence(2,"'", Repeat_until(AnyChar(),"'",wrap=JoinSubstring)),
                   !Sequence(decimals, "%"),
                   !Sequence(CharIn("+-"), decimals),
                   !Repeat1(word),
                   !Sequence("#", Repeat(6,6,hex_digit)))
        ));

attributes = join(attribute_parser, whitespace_maybe);

parse(attributes,"a = 1 b=6% font=\"+1asd\" some=word color=#ffffff increment=+1 decrement=-1") ==
[ "a" => "1", "b" => "6%", "font" => "+1asd", "some" => "word", "color" => "#ffffff",
  "increment" => "+1", "decrement" => "-1" ]



@testset "continue options of last Either" begin
    @test parse(attributes, "size=10% class=1") == [ "size"=>"10%", "class"=>"1" ]
end

function html(tags::CombinedParser, inner::CombinedParser, attrs=attributes)
    html(result_type(inner), tags, attrs) do until
        Repeat_until(inner, until)
    end
end

function html(inner::Function, T::Type, tags::CombinedParser, attrs_parser=attributes)
    A = eltype(result_type(attrs_parser))
    function nested_html(x,)
        (tag,attrs) = x
        Either{Any}(map(parser("/>")) do v
                    (tag=tag, attrs=attrs, children=T[])
                    end,
                    Sequence(">",
                             inner(Sequence("</",tag,">"))) do v
                    (tag=tag, attrs=attrs, children=v[2])
                    end)
    end
    FlatMap{Any}(
        nested_html,
        Sequence(
            2,
            "<",
            Sequence(
                tags,
                Optional(Sequence(
                    2,
                    whitespace_horizontal,
                    attrs_parser,
                    whitespace_maybe)))))
end


@testset "html" begin
    inner = Either{Any}(Any[!Repeat(CharNotIn("<>"))]);
    pushfirst!(inner,html(!Repeat1(ValueIn('a':'z')),inner,attributes));
    parse(inner,"<a font=1><b>b</b>a</a>")
    @test parse(inner,"<a font=\"+1\">i<b>bold</b>j</a>") == 
        (tag="a", attrs=["font"=>"+1"], children=[
            "i",
            (tag="b", attrs=[], children=["bold"]),
            "j"])

    @test parse(inner,"<a font=+1/>") ==
        (tag="a", attrs=["font"=>"+1"], children=[])
end                  
