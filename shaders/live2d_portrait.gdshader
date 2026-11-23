shader_type canvas_item;
// 伪 Live2D 立绘动态着色器：呼吸起伏、头发微风摆动、2.5D 鼠标视线跟随、点击回弹与边缘流光

uniform float time_sec = 0.0;
uniform vec2 look_offset = vec2(0.0, 0.0); // -1..1 鼠标相对偏移
uniform float bounce = 0.0;                // 点击互动弹跳强度 (0..1)
uniform float flash = 0.0;                 // 切换角色/互动闪光
uniform vec4 glow_color : source_color = vec4(1.0, 0.85, 0.5, 1.0);

void fragment() {
	vec2 uv = UV;
	// 越靠近底部越固定，越靠近头部/发梢形变越明显（模拟立绘重心）
	float upper = clamp(1.0 - uv.y, 0.0, 1.0);
	float upper_sq = upper * upper;

	// 1. 胸口呼吸：周期约 3.2 秒，胸腹区域轻微上下/横向伸缩
	float breath = sin(time_sec * 1.95);
	float chest_mask = exp(-pow((uv.y - 0.50) / 0.24, 2.0));
	uv.y += breath * 0.0045 * upper;
	uv.x = (uv.x - 0.5) * (1.0 - breath * 0.011 * chest_mask) + 0.5;

	// 2. 身体轻晃 + 两侧发梢柔和风动（带相位差）
	float sway = sin(time_sec * 1.15) * 0.0055 * upper_sq;
	float edge_x = clamp(abs(uv.x - 0.5) * 2.0 - 0.18, 0.0, 1.0);
	float hair_wave = sin(time_sec * 2.7 + uv.y * 7.5 + uv.x * 3.0) * 0.0055 * edge_x * clamp(1.1 - uv.y * 0.7, 0.0, 1.0);
	uv.x += sway + hair_wave;

	// 3. 2.5D 鼠标视线跟随（头部倾斜与轻微透视位移）
	uv.x -= look_offset.x * 0.022 * upper;
	uv.y -= look_offset.y * 0.014 * upper;
	// 轻微俯仰缩放
	float tilt_scale = 1.0 + look_offset.x * (uv.x - 0.5) * 0.025 * upper;
	uv.y = (uv.y - 0.5) * tilt_scale + 0.5;

	// 4. 点击互动弹性缩放（以中下部为支点）
	if (bounce > 0.001) {
		float sx = 1.0 + bounce * 0.045;
		float sy = 1.0 - bounce * 0.035;
		uv.x = (uv.x - 0.5) / sx + 0.5;
		uv.y = (uv.y - 0.85) / sy + 0.85;
	}

	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0);
	} else {
		vec4 col = texture(TEXTURE, uv);
		// 柔和扫光流影（约每 5 秒划过一次立绘）
		float sheen_pos = mod(time_sec * 0.42, 3.2) - 0.8;
		float sheen = exp(-pow((uv.x * 0.7 + uv.y * 0.5 - sheen_pos) / 0.09, 2.0)) * 0.14;
		col.rgb += glow_color.rgb * sheen * col.a;
		// 互动轻微提亮
		col.rgb = mix(col.rgb, col.rgb + glow_color.rgb * 0.25, flash * 0.5);
		COLOR = col;
	}
}
