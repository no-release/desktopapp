extends Control

const LIMIT := 24

@onready var site_option: OptionButton = %SiteOption
@onready var rating_option: OptionButton = %RatingOption
@onready var tags_edit: LineEdit = %TagsEdit
@onready var search_button: Button = %SearchButton
@onready var prev_button: Button = %PrevButton
@onready var next_button: Button = %NextButton
@onready var page_label: Label = %PageLabel
@onready var status_label: Label = %StatusLabel
@onready var grid: GridContainer = %Grid
@onready var http: HTTPRequest = %HTTPRequest
@onready var image_http: HTTPRequest = %ImageHTTPRequest
@onready var preview_dialog: AcceptDialog = %PreviewDialog
@onready var preview_texture: TextureRect = %PreviewTexture
@onready var preview_meta: Label = %PreviewMeta

var page := 0
var last_posts: Array = []
var pending_textures: Dictionary = {} # HTTPRequest id -> TextureRect
var preview_queue: Array = []
var fetching_preview := false
var current_full_url := ""

func _ready() -> void:
	site_option.clear()
	site_option.add_item("Safebooru (SFW)", BooruClient.Site.SAFEBOORU)
	site_option.add_item("Gelbooru", BooruClient.Site.GELBOORU)
	site_option.add_item("Danbooru", BooruClient.Site.DANBOORU)
	site_option.add_item("Rule34", BooruClient.Site.RULE34)
	site_option.select(0)

	rating_option.clear()
	rating_option.add_item("safe", 0)
	rating_option.add_item("questionable", 1)
	rating_option.add_item("explicit", 2)
	rating_option.add_item("any", 3)
	rating_option.select(0)

	tags_edit.text = "cat_ears 1girl"
	tags_edit.text_submitted.connect(func(_t): _search(true))
	search_button.pressed.connect(func(): _search(true))
	prev_button.pressed.connect(_prev_page)
	next_button.pressed.connect(_next_page)
	site_option.item_selected.connect(_on_site_changed)
	http.request_completed.connect(_on_search_completed)
	image_http.request_completed.connect(_on_image_completed)

	_set_busy(false)
	status_label.text = "Pick a site, enter tags, then Search."

func _on_site_changed(idx: int) -> void:
	var site: BooruClient.Site = site_option.get_item_id(idx) as BooruClient.Site
	if site == BooruClient.Site.SAFEBOORU:
		rating_option.select(0)
	elif site == BooruClient.Site.RULE34:
		rating_option.select(2)

func _current_site() -> BooruClient.Site:
	return site_option.get_item_id(site_option.selected) as BooruClient.Site

func _current_rating() -> String:
	return rating_option.get_item_text(rating_option.selected)

func _search(reset_page: bool) -> void:
	if reset_page:
		page = 0
	_clear_grid()
	_set_busy(true)
	status_label.text = "Searching..."
	var url := BooruClient.build_url(_current_site(), tags_edit.text, page, LIMIT, _current_rating())
	var err := http.request(url, PackedStringArray(["User-Agent: BooruGodot/1.0"]))
	if err != OK:
		_set_busy(false)
		status_label.text = "Failed to start request (%s)." % err

func _prev_page() -> void:
	if page > 0:
		page -= 1
		_search(false)

func _next_page() -> void:
	page += 1
	_search(false)

func _on_search_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_set_busy(false)
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		status_label.text = "Request failed (%s / HTTP %s)." % [result, response_code]
		return
	last_posts = BooruClient.parse_posts(_current_site(), body)
	page_label.text = "Page %d" % (page + 1)
	if last_posts.is_empty():
		status_label.text = "No posts. Try different tags or another page."
		return
	status_label.text = "Loaded %d posts." % last_posts.size()
	_populate_grid(last_posts)

func _clear_grid() -> void:
	preview_queue.clear()
	fetching_preview = false
	for child in grid.get_children():
		child.queue_free()

func _populate_grid(posts: Array) -> void:
	for post in posts:
		var built: Dictionary = _make_cell(post)
		grid.add_child(built["cell"])
		preview_queue.append({"url": post["preview"], "rect": built["thumb"]})
	_pump_preview_queue()

func _make_cell(post: Dictionary) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(180, 220)
	var v := VBoxContainer.new()
	v.name = "Box"
	panel.add_child(v)

	var thumb := TextureRect.new()
	thumb.name = "Thumb"
	thumb.custom_minimum_size = Vector2(170, 170)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.mouse_filter = Control.MOUSE_FILTER_STOP
	thumb.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_open_preview(post)
	)
	v.add_child(thumb)

	var cap := Label.new()
	cap.text = "#%s  %s" % [post.get("id", "?"), str(post.get("rating", ""))]
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cap.clip_text = true
	v.add_child(cap)
	return {"cell": panel, "thumb": thumb}

func _pump_preview_queue() -> void:
	if fetching_preview or preview_queue.is_empty():
		return
	fetching_preview = true
	var job: Dictionary = preview_queue.pop_front()
	image_http.set_meta("target", job["rect"])
	image_http.set_meta("kind", "thumb")
	var err := image_http.request(job["url"], PackedStringArray(["User-Agent: BooruGodot/1.0"]))
	if err != OK:
		fetching_preview = false
		_pump_preview_queue()

func _on_image_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var kind := str(image_http.get_meta("kind", "thumb"))
	if kind == "full":
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var tex := _image_to_texture(body)
			if tex:
				preview_texture.texture = tex
		fetching_preview = false
		_pump_preview_queue()
		return

	var target = image_http.get_meta("target", null)
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200 and target is TextureRect and is_instance_valid(target):
		var tex := _image_to_texture(body)
		if tex:
			target.texture = tex
	fetching_preview = false
	_pump_preview_queue()

func _image_to_texture(body: PackedByteArray) -> Texture2D:
	if body.size() < 12:
		return null
	var img := Image.new()
	var err := FAILED
	# Detect format so Godot does not print "Not a PNG file" for JPEGs.
	if body[0] == 0xFF and body[1] == 0xD8:
		err = img.load_jpg_from_buffer(body)
	elif body[0] == 0x89 and body[1] == 0x50 and body[2] == 0x4E and body[3] == 0x47:
		err = img.load_png_from_buffer(body)
	elif body[0] == 0x52 and body[1] == 0x49 and body[2] == 0x46 and body[3] == 0x46:
		err = img.load_webp_from_buffer(body)
	else:
		err = img.load_jpg_from_buffer(body)
		if err != OK:
			err = img.load_webp_from_buffer(body)
		if err != OK:
			err = img.load_png_from_buffer(body)
	if err != OK or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)

func _open_preview(post: Dictionary) -> void:
	preview_meta.text = "%s  #%s  rating:%s\n%s\n%s" % [
		post.get("site", ""),
		post.get("id", ""),
		post.get("rating", ""),
		post.get("full", ""),
		str(post.get("tags", "")).left(400),
	]
	preview_texture.texture = null
	preview_dialog.popup_centered_ratio(0.85)
	current_full_url = str(post.get("full", ""))
	if current_full_url == "":
		return
	# Reuse image HTTP after current thumb finishes; insert full at front.
	preview_queue.push_front({"url": current_full_url, "rect": preview_texture, "full": true})
	# If idle, start immediately as full.
	if not fetching_preview:
		fetching_preview = true
		var job: Dictionary = preview_queue.pop_front()
		image_http.set_meta("target", job.get("rect"))
		image_http.set_meta("kind", "full" if job.get("full", false) else "thumb")
		image_http.request(job["url"], PackedStringArray(["User-Agent: BooruGodot/1.0"]))

func _set_busy(busy: bool) -> void:
	search_button.disabled = busy
	prev_button.disabled = busy or page == 0
	next_button.disabled = busy
	tags_edit.editable = not busy
