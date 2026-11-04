from colourEmoji import base, save, squares

order = [".notdef", "u1F600", "u1D11E"]
builder = base(
    "Void Line Shapes", order,
    {0x1F600: "u1F600", 0x1D11E: "u1D11E"}, squares(order), 900,
)
save(builder.font, "lineShapesFallback.ttf")
