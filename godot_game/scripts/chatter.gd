class_name Chatter
extends Node2D
## A tiny speech bubble above a unit's head with a snarky line, shown when the unit is given an order.

static var enabled := true

const LINES := {
	"move": ["Walking. My favourite.", "Oh sure, over THERE.", "Are we there yet?", "My feet filed a complaint.",
		"Left, right, repeat.", "Moving. Under protest.", "I had plans. Anyway.", "Lead on, oh wise one.",
		"Is this a shortcut? It's not.", "On my way. Slowly.",
		"Fine, but I'm not skipping.", "Another stroll. How delightful.", "Walking is just falling with style.", "I'll get there. Eventually.", "Do I look like I have a map?", "Sure, let me just teleport. Oh wait.", "Is this a team-building exercise?", "Step one: walk. Step two: complain."],
	"wood": ["Trees. Again.", "I'll show that tree who's boss.", "Timber! Obviously.", "Axe-cellent choice.",
		"Tree: 0. Me: whatever.", "Hope it doesn't fight back.", "Chop, chop. Literally.", "Wood you believe it?",
		"This tree owes me money.", "Sap happens.", "I'm on a roll. Not a log roll.", "Tree-mendous.", "Leaf me alone, I'm chopping.", "Bark worse than its bite.", "Splinters are just free tattoos."],
	"food": ["Berries! Finally, some joy.", "Nature's snack bar.", "If I eat one, is it stealing?", "Fruit picking, my dream career.",
		"Hand me a basket.", "Just berry-ing along.",
		"Berry nice of you.", "Vitamin C, here I come.", "Pick, eat, regret nothing.", "Are these safe? Eh, they look fine.", "The best things in life are berries."],
	"gold": ["Gold! Mine, mine, all mine.", "Shiny. Must dig.", "Rock and stone, I guess.", "Digging for riches. Or backache.",
		"Pickaxe time. Joy.", "I'm not saying I'm rich. Yet.",
		"I knew I'd strike it rich.", "All that glitters, sure.", "Digging my own grave? No, gold.", "My back hurts and I love it.", "Rich in spirit. Poor in everything else."],
	"stone": ["Rocks. Thrilling.", "Heavy. So heavy.", "I'm a rock star now.", "Between a rock and a hard job.",
		"Stone cold. Like my enthusiasm.", "Can't wait to carry this.",
		"Rock bottom, again.", "Rocks fall, everyone digs.", "Stone me once, shame on you.", "I'll just carry this tiny boulder.", "Hard work? More like hard rock."],
	"build": ["Built it once, can build it again.", "Where's the blueprint? Oh wait.", "Hammer time!", "Measure once, hope twice.",
		"Looks stable. Probably.", "Builder? I hardly know her.", "Nail it. Or bang it. Either way.",
		"A house is just a very big hat.", "Who needs plans? Not me.", "Hammer, nails, bad ideas. Let's go.", "I'll build it. I won't live in it.", "Load-bearing optimism.", "Under construction. Like my patience.", "Wall? Wall right then.", "Stack it high, pray it holds.", "Another masterpiece. Or a shed."],
	"repair": ["Duct tape and hope.", "It's not broken, it's rustic.", "Fixing what you broke. Again.", "Patch job, coming up.",
		"I fix, you stress.", "Good as new. Mostly.",
		"Held together by spite.", "Fixed! Don't touch it.", "Nothing a little glue can't do.", "Who broke it this time?", "Medic! Er, carpenter!"],
	"farm": ["Farming. Glamorous.", "Crops don't plant themselves. Sadly.", "I'd rather be bored elsewhere.", "Grow, little plants, grow.",
		"Another day in the field.", "Moo-ve over, I'm farming.",
		"Dirt under my nails. Again.", "Some day this will be bread.", "Seeds of doubt, planted.", "Crop circles? Just me.", "Plow, sow, regret, repeat."],
	"attack": ["For glory! Or lunch.", "Charge! Someone go first.", "This'll sting. Them, hopefully.", "I'm not paid enough for this.",
		"Time to be a hero.", "Sharp end goes forward, right?", "Ow-ready? Because I'm not.", "Finally, some violence.",
		"Hold my helmet!", "I've had worse Mondays.", "Poke first, ask later.", "Tell my mother I was brave.", "Let's dance, ugly.", "Violence is the answer. What's the question?", "Sir, I have a bad feeling."],
	"hurt": ["Ow! That's my face!", "Help! Somebody! Anybody!", "Run away! Run away!", "I'm too pretty to die!",
		"Not the face!", "Why me?!", "Mommy?!", "I just work here!", "Tell my cow I loved her!", "Rude!", "AAAH! Teeth!",
		"This is not in my contract!", "I demand a refund!", "Ouch. Ouch. Ouch.", "Violence?! In THIS economy?!"],
	"soldier_hurt": ["Just a scratch!", "That's gonna leave a mark.", "Okay, now I'm annoyed.", "Medic! Anyone? No?", "Bold move. Dumb, but bold.",
		"I felt that in my soul.", "Is that all you've got?", "Rude. Also painful.", "My armor's for show, apparently.", "Oh, it's on now."],
	# archer towers, when they open fire and when they land a kill
	"tower": ["Sniper mode: on.", "Target acquired.", "Incoming! ...for them.", "Locked and loaded.", "Say cheese.",
		"I see you.", "Nobody sneaks past me.", "Eyes on target.", "Breathe in... and release.", "Open season!",
		"Stand still, this won't hurt. Much.", "Arrows: sharp. Aim: sharper.", "Welcome to the shooting gallery."],
	"tower_kill": ["Boom, headshot!", "Right between the eyes.", "Nothing personal.", "One shot, one kill.", "Next!",
		"Bullseye!", "And stay down.", "That's how it's done.", "Too easy.", "Robin Hood who?", "Sniped.",
		"Better luck next life.", "Delivered. No tip needed.", "Headshot! Do I get a medal?", "Pew pew. Wait, wrong game."],
	# a monk who has just converted someone, and one who picks up or delivers a relic
	"convert": ["Welcome to the right side.", "Your old boss won't mind. Much.", "Have you considered a career change?",
		"Say hello to your new employer.", "Believe. It's easier.", "Another soul saved. Mine, now.",
		"Don't thank me. Tithes are optional. (They aren't.)", "Free will is overrated.", "Chanting works. Who knew?",
		"You were never really theirs.", "Sign here. No, here. Wonderful."],
	"relic": ["Heavy. Holy. Heavy.", "I'm only the delivery monk.", "Don't drop the sacred thing.", "Pray it doesn't get stolen.",
		"This weighs more than my faith.", "Careful with the shiny box.", "Gold falls from heaven. Slowly.", "Finders keepers, Monastery sleepers."],
	"soldier_move": ["Marching. Gloriously.", "Orders are orders. Sigh.", "Boots on the ground, complaints in the air.",
		"Do I get hazard pay?", "Yes, sir. Sarcasm included.", "Left, right, left, regret.",
		"Quick march. Slow complain.", "My boots are my only friends.", "Moving out. Eventually.", "Yes, general. Right away. Sure.", "Are we the baddies? Asking for a friend."],
}

var text := ""
var t := 0.0

var _font: Font
var _size := 17


static func say(unit: Node2D, category: String, chance := 1.0) -> void:
	if randf() > chance or not enabled or not LINES.has(category) or not is_instance_valid(unit):
		return
	if unit.has_node("Chatter"):
		return
	var lines: Array = LINES[category]
	var c := Chatter.new()
	c.name = "Chatter"
	c.text = lines[randi() % lines.size()]
	c.z_index = 60
	var head: Variant = unit.get("bar_y")
	c.position = Vector2(0, -(float(head) if head != null else float(unit.call("_top")) + 10.0) - 26.0)
	unit.add_child(c)


## A few of the ordered units speak, not the whole crowd.
static func say_some(units: Array, category: String, soldier_category := "") -> void:
	if not enabled or units.is_empty():
		return
	var pool := units.duplicate()
	pool.shuffle()
	for i in mini(2, pool.size()):
		var u: Node2D = pool[i]
		var cat := category
		if soldier_category != "" and u is Soldier:
			cat = soldier_category
		say(u, cat)


func _ready() -> void:
	_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	t += delta
	if t >= 3.2:
		queue_free()
		return
	modulate.a = 1.0 if t < 2.6 else (3.2 - t) / 0.6
	queue_redraw()


func _draw() -> void:
	if _font == null:
		return
	var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _size)
	var pad := Vector2(9, 5)
	var r := Rect2(Vector2(-sz.x * 0.5 - pad.x, -sz.y - pad.y * 2.0), sz + pad * 2.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.98, 0.9, 0.95)
	sb.border_color = Color(0.2, 0.14, 0.06)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(9)
	draw_style_box(sb, r)
	# little tail pointing at the head
	var tip := Vector2(0, r.end.y + 8.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-6, r.end.y - 1), Vector2(6, r.end.y - 1), tip]), Color(1, 0.98, 0.9, 0.95))
	draw_line(Vector2(-6, r.end.y), tip, Color(0.2, 0.14, 0.06), 2.0)
	draw_line(Vector2(6, r.end.y), tip, Color(0.2, 0.14, 0.06), 2.0)
	draw_string(_font, Vector2(-sz.x * 0.5, r.position.y + pad.y + _font.get_ascent(_size)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, _size, Color(0.12, 0.08, 0.03))
