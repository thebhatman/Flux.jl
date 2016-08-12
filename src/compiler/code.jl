function process_func(ex, params)
  @capture(shortdef(ex), (args__,) -> body_)
  body = il(graphm(body))
  body = map(x -> x in params ? :(self.$x) : x, body)
  return args, body
end

function build_type(T, params)
  quote
    type $T
      $(params...)
      $([symbol("Δ", s) for s in params]...)
    end
    $T($(params...)) = $T($(params...),
                          $((:(zeros($p)) for p in params)...))
  end
end

function build_forward(body, args)
  cse(body)
end

function build_backward(body, x, params)
  Δs = invert(body)
  back = IVertex{Any}(Flow.Do())
  for param in params
    haskey(Δs, :(self.$param)) || continue
    k = symbol("Δ", param)
    ksym = Expr(:quote, k)
    ex = Δs[:(self.$param)]
    thread!(back, @v(setfield!(:self, ksym, :(self.$k) + ex)))
  end
  ex = Δs[x]
  thread!(back, @flow(tuple($ex)))
  cse(back)
end

function build_update(T, params)
  updates = []
  for p in params
    Δp = symbol("Δ", p)
    push!(updates, :(self.$p += self.$Δp; fill!(self.$Δp, 0)))
  end
  :(update!(self::$T) = $(updates...))
end

function process_type(ex)
  @capture(ex, type T_ fs__ end)
  @destruct [params = true || [],
             funcs  = false || []] = groupby(x->isa(x, Symbol), fs)
  @assert length(funcs) == 1
  args, body = process_func(funcs[1], params)
  @assert length(args) == 1
  quote
    $(build_type(T, params))
    (self::$T)($(args...),) = $(syntax(build_forward(body, args)))
    back!(self::$T, Δ, $(args...)) = $(syntax(build_backward(body, args[1], params)))
    $(build_update(T, params))
  end |> longdef
end

# process_type(:(type Sigmoid
#   W
#   b
#   x -> σ(W*x+b)
# end)) |> prettify
