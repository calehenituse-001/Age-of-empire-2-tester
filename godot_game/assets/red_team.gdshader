shader_type canvas_item;
// The player's colour is baked into the sprites as blue; the rival's buildings swap it for red.
// COLOR already holds the texel times the modulate colour when fragment() starts.
void fragment() {
	vec4 c = COLOR;
	if (c.b > c.r * 1.3 && c.b > c.g * 1.1 && c.b > 0.25) {
		c.rgb = vec3(c.b, c.g * 0.8, c.r);
	}
	COLOR = c;
}
