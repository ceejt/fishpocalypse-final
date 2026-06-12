shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.29;
uniform float scanline_count : hint_range(10.0, 600.0) = 10.0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.55;
uniform float aberration : hint_range(0.0, 0.1) = 0.01;
uniform float wave_speed : hint_range(0.0, 5.0) = 1.5;
uniform float wave_strength : hint_range(0.0, 0.02) = 0.004;

void fragment() {
	vec2 uv = SCREEN_UV;

	// rolling wave distortion
	uv.x += sin(uv.y * 20.0 + TIME * wave_speed) * wave_strength;
	uv.y += cos(uv.x * 15.0 + TIME * wave_speed * 0.7) * wave_strength * 0.5;

	// chromatic aberration
	float r = texture(SCREEN_TEXTURE, uv + vec2(aberration, 0.0)).r;
	float g = texture(SCREEN_TEXTURE, uv).g;
	float b = texture(SCREEN_TEXTURE, uv - vec2(aberration, 0.0)).b;
	vec4 color = vec4(r, g, b, 1.0);

	// animated scanlines that scroll downward
	float scanline = sin(uv.y * scanline_count * 3.14159 - TIME * 0.5) * 0.5 + 0.5;
	scanline = pow(scanline, 0.5);
	color.rgb *= 1.0 - scanline_strength * (1.0 - scanline);

	// vignette
	vec2 vig_uv = uv * (1.0 - uv.yx);
	float vignette = pow(vig_uv.x * vig_uv.y * 15.0, vignette_strength);
	color.rgb *= vignette;

	COLOR = color;
}