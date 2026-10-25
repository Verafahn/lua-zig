---@diagnostic disable: undefined-global

local squares = {}
for i = 1, 4 do
    squares[i] = i * i
end
return string.format(
    "Hello from %s\ninterpreter: %s\nsquares: %s\nsum: %d\n",
    host_greeting(), _VERSION, table.concat(squares, ", "), add(10))
