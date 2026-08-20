shader_type canvas_item;

uniform sampler2D parchment_texture : source_color;

void fragment() {
	vec4 paper = texture(parchment_texture, SCREEN_UV);
	COLOR = paper * COLOR;
}