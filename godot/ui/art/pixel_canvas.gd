class_name PixelCanvas
extends RefCounted
## A few pygame.draw look-alikes on an Image (rect, ellipse, circle, polygon, line, arc), used to
## paint the placeholder sprites and the minimap arrow. Everything is binary: a pixel is either
## written or left alone, so alpha stays 0 or 255 as the art bible asks. Out-of-range pixels are
## skipped (pygame clips the same way).

var image: Image


## A transparent RGBA canvas of size x size, or pass an existing Image to draw on it.
func _init(size: int = 32, existing: Image = null) -> void:
	if existing != null:
		image = existing
	else:
		image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)


## One pixel.
func set_at(x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
		image.set_pixel(x, y, c)


## pygame.draw.rect(surface, c, (x, y, w, h)).
func rect(x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(maxi(0, y), mini(image.get_height(), y + h)):
		for xx in range(maxi(0, x), mini(image.get_width(), x + w)):
			image.set_pixel(xx, yy, c)


## pygame.draw.ellipse(surface, c, (x, y, w, h)): the ellipse inscribed in the rectangle.
func ellipse(x: int, y: int, w: int, h: int, c: Color) -> void:
	var cx := x + w / 2.0
	var cy := y + h / 2.0
	var rx := w / 2.0
	var ry := h / 2.0
	for yy in range(maxi(0, y), mini(image.get_height(), y + h)):
		var dy := (yy + 0.5 - cy) / ry
		for xx in range(maxi(0, x), mini(image.get_width(), x + w)):
			var dx := (xx + 0.5 - cx) / rx
			if dx * dx + dy * dy <= 1.0:
				image.set_pixel(xx, yy, c)


## pygame.draw.circle(surface, c, (cx, cy), r, width): width 0 fills, 1 draws a ring. Pixels strictly inside
## the radius (so a radius 5 head has no one pixel spikes, as pygame draws it).
func circle(cx: int, cy: int, r: int, c: Color, width: int = 0) -> void:
	for yy in range(cy - r, cy + r + 1):
		for xx in range(cx - r, cx + r + 1):
			var d2 := (xx - cx) * (xx - cx) + (yy - cy) * (yy - cy)
			if d2 < r * r + (1 if r <= 2 else 0) and (width == 0 or d2 > (r - width) * (r - width)):
				set_at(xx, yy, c)


## pygame.draw.polygon, filled: the pixels whose centres are inside, plus the edges.
func polygon(points: Array[Vector2], c: Color) -> void:
	var n := points.size()
	var y_min := floori(points[0].y)
	var y_max := ceili(points[0].y)
	for p in points:
		y_min = mini(y_min, floori(p.y))
		y_max = maxi(y_max, ceili(p.y))
	for yy in range(maxi(0, y_min), mini(image.get_height(), y_max + 1)):
		var xs: Array[float] = []
		var sy := yy + 0.5
		for i in n:
			var a := points[i]
			var b := points[(i + 1) % n]
			if (a.y <= sy and b.y > sy) or (b.y <= sy and a.y > sy):
				xs.append(a.x + (sy - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			for xx in range(maxi(0, ceili(xs[k] - 0.5)), mini(image.get_width(), floori(xs[k + 1] - 0.5) + 1)):
				image.set_pixel(xx, yy, c)
	for i in n:
		line(points[i], points[(i + 1) % n], c)


## A one-pixel polygon outline (pygame.draw.polygon with width 1).
func polygon_outline(points: Array[Vector2], c: Color) -> void:
	for i in points.size():
		line(points[i], points[(i + 1) % points.size()], c)


## pygame.draw.line: Bresenham between the (truncated) end points; width 2 stamps 2 x 2 pixels.
func line(a: Vector2, b: Vector2, c: Color, width: int = 1) -> void:
	var x0 := int(a.x)
	var y0 := int(a.y)
	var x1 := int(b.x)
	var y1 := int(b.y)
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		for ox in width:
			for oy in width:
				set_at(x0 + ox, y0 + oy, c)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy


## pygame.draw.lines(surface, c, false, points, 1).
func lines(points: Array[Vector2], c: Color) -> void:
	for i in points.size() - 1:
		line(points[i], points[i + 1], c)


## pygame.draw.arc(surface, c, (x, y, w, h), start, stop, 1): angles in radians, counter-clockwise
## from the right as drawn on screen.
func arc(x: int, y: int, w: int, h: int, start: float, stop: float, c: Color) -> void:
	var cx := x + w / 2.0
	var cy := y + h / 2.0
	var steps := int(maxf(w, h) * 4.0)
	for i in steps + 1:
		var t := start + (stop - start) * i / steps
		set_at(int(cx + w / 2.0 * cos(t)), int(cy - h / 2.0 * sin(t)), c)
