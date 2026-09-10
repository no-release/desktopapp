extends RefCounted
class_name BooruClient

enum Site { SAFEBOORU, GELBOORU, DANBOORU, RULE34 }

static func site_name(site: Site) -> String:
	match site:
		Site.SAFEBOORU:
			return "Safebooru"
		Site.GELBOORU:
			return "Gelbooru"
		Site.DANBOORU:
			return "Danbooru"
		Site.RULE34:
			return "Rule34"
	return "Unknown"

static func default_rating(site: Site) -> String:
	# Prefer safe unless the user picks an explicit site.
	if site == Site.RULE34:
		return "explicit"
	return "safe"

static func build_url(site: Site, tags: String, page: int, limit: int, rating: String) -> String:
	var tag_list := tags.strip_edges()
	if rating != "" and rating != "any":
		if not tag_list.contains("rating:"):
			tag_list = ("rating:%s %s" % [rating, tag_list]).strip_edges()
	var encoded := tag_list.uri_encode()
	match site:
		Site.SAFEBOORU:
			return "https://safebooru.org/index.php?page=dapi&s=post&q=index&json=1&limit=%d&pid=%d&tags=%s" % [limit, page, encoded]
		Site.GELBOORU:
			# Gelbooru public JSON (no API key required for light use).
			return "https://gelbooru.com/index.php?page=dapi&s=post&q=index&json=1&limit=%d&pid=%d&tags=%s" % [limit, page, encoded]
		Site.DANBOORU:
			# Danbooru pages are 1-indexed.
			return "https://danbooru.donmai.us/posts.json?limit=%d&page=%d&tags=%s" % [limit, page + 1, encoded]
		Site.RULE34:
			return "https://api.rule34.xxx/index.php?page=dapi&s=post&q=index&json=1&limit=%d&pid=%d&tags=%s" % [limit, page, encoded]
	return ""

static func parse_posts(site: Site, body: PackedByteArray) -> Array:
	var text := body.get_string_from_utf8()
	if text.strip_edges() == "":
		return []
	var data = JSON.parse_string(text)
	if data == null:
		return []
	var raw: Array = []
	if site == Site.GELBOORU and typeof(data) == TYPE_DICTIONARY and data.has("post"):
		raw = data["post"]
	elif typeof(data) == TYPE_ARRAY:
		raw = data
	else:
		return []
	var out: Array = []
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var post := normalize_post(site, item)
		if post.get("preview", "") != "":
			out.append(post)
	return out

static func normalize_post(site: Site, item: Dictionary) -> Dictionary:
	var preview := ""
	var full := ""
	var post_id := str(item.get("id", ""))
	var tags := str(item.get("tags", item.get("tag_string", "")))
	var rating := str(item.get("rating", ""))
	var source := str(item.get("source", ""))
	match site:
		Site.DANBOORU:
			preview = str(item.get("preview_file_url", item.get("preview_url", "")))
			full = str(item.get("file_url", item.get("large_file_url", preview)))
		_:
			preview = str(item.get("preview_url", item.get("sample_url", "")))
			full = str(item.get("file_url", item.get("sample_url", preview)))
			# Some gelbooru-style APIs return relative paths.
			if preview.begins_with("//"):
				preview = "https:" + preview
			if full.begins_with("//"):
				full = "https:" + full
	return {
		"id": post_id,
		"preview": preview,
		"full": full,
		"tags": tags,
		"rating": rating,
		"source": source,
		"site": site_name(site),
	}
