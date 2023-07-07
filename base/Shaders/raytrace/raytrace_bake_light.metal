
using namespace metal;
using namespace raytracing;

struct Vertex {
	uint posxy;
	uint poszw;
	uint nor;
	uint tex;
};

struct RayGenConstantBuffer {
	float4 v0; // frame, strength, radius, offset
	float4 v1;
	float4 v2;
	float4 v3;
	float4 v4;
};

struct RayPayload {
	float4 color;
	float3 ray_origin;
	float3 ray_dir;
};

constant int SAMPLES = 64;

float2 equirect(float3 normal, float angle) {
	const float PI = 3.1415926535;
	const float PI2 = PI * 2.0;
	float phi = acos(normal.z);
	float theta = atan2(-normal.y, normal.x) + PI + angle;
	return float2(theta / PI2, phi / PI);
}

float rand(int pixel_i, int pixel_j, int sampleIndex, int sampleDimension, int frame, texture2d<float, access::read> sobol, texture2d<float, access::read> scramble, texture2d<float, access::read> rank) {
	pixel_i += frame * 9;
	pixel_j += frame * 11;
	pixel_i = pixel_i & 127;
	pixel_j = pixel_j & 127;
	sampleIndex = sampleIndex & 255;
	sampleDimension = sampleDimension & 255;

	int i = sampleDimension + (pixel_i + pixel_j * 128) * 8;
	int rankedSampleIndex = sampleIndex ^ int(rank.read(uint2(i % 128, uint(i / 128)), 0).r * 255);

	i = sampleDimension + rankedSampleIndex * 256;
	int value = int(sobol.read(uint2(i % 256, uint(i / 256)), 0).r * 255);

	i = (sampleDimension % 8) + (pixel_i + pixel_j * 128) * 8;
	value = value ^ int(scramble.read(uint2(i % 128, uint(i / 128)), 0).r * 255);

	float v = (0.5f + value) / 256.0f;
	return v;
}

float3 cos_weighted_hemisphere_direction(uint2 tid, float3 n, uint sample, uint seed, int frame, texture2d<float, access::read> sobol, texture2d<float, access::read> scramble, texture2d<float, access::read> rank) {
	const float PI = 3.1415926535;
	const float PI2 = PI * 2.0;
	float f0 = rand(tid.x, tid.y, sample, seed, frame, sobol, scramble, rank);
	float f1 = rand(tid.x, tid.y, sample, seed + 1, frame, sobol, scramble, rank);
	float z = f0 * 2.0f - 1.0f;
	float a = f1 * PI2;
	float r = sqrt(1.0f - z * z);
	float x = r * cos(a);
	float y = r * sin(a);
	return normalize(n + float3(x, y, z));
}

float3 hit_attribute(float3 vertexAttribute[3], float2 barycentrics) {
	return vertexAttribute[0] +
		barycentrics.x * (vertexAttribute[1] - vertexAttribute[0]) +
		barycentrics.y * (vertexAttribute[2] - vertexAttribute[0]);
}

float2 hit_attribute2d(float2 vertexAttribute[3], float2 barycentrics) {
	return vertexAttribute[0] +
		barycentrics.x * (vertexAttribute[1] - vertexAttribute[0]) +
		barycentrics.y * (vertexAttribute[2] - vertexAttribute[0]);
}

float2 s16_to_f32(uint val) {
	int a = (int)(val << 16) >> 16;
	int b = (int)(val & 0xffff0000) >> 16;
	return float2(a, b) / 32767.0f;
}

kernel void raytracingKernel(
	uint2 tid [[thread_position_in_grid]],
	constant RayGenConstantBuffer &constant_buffer [[buffer(0)]],
	texture2d<float, access::read_write> render_target [[texture(0)]],
	texture2d<float, access::read> mytexture0 [[texture(1)]],
	texture2d<float, access::read> mytexture1 [[texture(2)]],
	texture2d<float, access::read> mytexture2 [[texture(3)]],
	texture2d<float, access::read> mytexture_env [[texture(4)]],
	texture2d<float, access::read> mytexture_sobol [[texture(5)]],
	texture2d<float, access::read> mytexture_scramble [[texture(6)]],
	texture2d<float, access::read> mytexture_rank [[texture(7)]],
	instance_acceleration_structure scene [[buffer(1)]],
	device void *indices [[buffer(2)]],
	device void *vertices [[buffer(3)]]
) {
	uint seed = 0;

	float2 xy = float2(tid) + float2(0.5f, 0.5f);
	float4 tex0 = mytexture0.read(uint2(xy), 0);
	if (tex0.a == 0.0) {
		render_target.write(float4(0.0f, 0.0f, 0.0f, 0.0f), tid);
		return;
	}
	float3 pos = tex0.rgb;
	float3 nor = mytexture1.read(uint2(xy), 0).rgb;

	RayPayload payload;

	ray ray;
	ray.min_distance = constant_buffer.v0.w * 0.01;
	ray.max_distance = constant_buffer.v0.z * 10.0;
	ray.origin = pos;
	float3 accum = float3(0, 0, 0);

	for (int i = 0; i < SAMPLES; ++i) {
		ray.direction = cos_weighted_hemisphere_direction(tid, nor, i, seed, constant_buffer.v0.x, mytexture_sobol, mytexture_scramble, mytexture_rank);
		seed += 1;

		intersector<triangle_data, instancing> in;
		in.assume_geometry_type(geometry_type::triangle);
		in.force_opacity(forced_opacity::opaque);
		in.accept_any_intersection(false);

		typename intersector<triangle_data, instancing>::result_type intersection;
		intersection = in.intersect(ray, scene);
		if (intersection.type == intersection_type::none) {
			float2 tex_coord = equirect(ray.direction, constant_buffer.v1.z);
			uint2 size = uint2(mytexture_env.get_width(), mytexture_env.get_height());
			float3 texenv = mytexture_env.read(uint2(tex_coord * float2(size)), 0).rgb * constant_buffer.v1.x;
			payload.color = float4(texenv.rgb, -1);
		}
		else {
			device uint32_t *inda = (device uint32_t *)(indices);
			uint3 indices_sample = uint3(
				inda[intersection.primitive_id * 3],
				inda[intersection.primitive_id * 3 + 1],
				inda[intersection.primitive_id * 3 + 2]
			);

			device Vertex *verta = (device Vertex *)(vertices);
			float3 vertex_normals[3] = {
				float3(s16_to_f32(verta[indices_sample[0]].nor), s16_to_f32(verta[indices_sample[0]].poszw).y),
				float3(s16_to_f32(verta[indices_sample[1]].nor), s16_to_f32(verta[indices_sample[1]].poszw).y),
				float3(s16_to_f32(verta[indices_sample[2]].nor), s16_to_f32(verta[indices_sample[2]].poszw).y)
			};
			float2 barycentrics = intersection.triangle_barycentric_coord;
			float3 n = normalize(hit_attribute(vertex_normals, barycentrics));

			float2 vertex_uvs[3] = {
				s16_to_f32(verta[indices_sample[0]].tex),
				s16_to_f32(verta[indices_sample[1]].tex),
				s16_to_f32(verta[indices_sample[2]].tex)
			};
			float2 tex_coord = hit_attribute2d(vertex_uvs, barycentrics);

			uint2 size = uint2(mytexture2.get_width(), mytexture2.get_height());
			float3 texpaint2 = pow(mytexture2.read(uint2(tex_coord * float2(size)), 0).rgb, 2.2); // layer base
			payload.color.rgb = texpaint2.rgb;
		}

		accum += payload.color.rgb;
	}

	accum /= SAMPLES;

	float3 texpaint2 = mytexture2.read(uint2(xy), 0).rgb; // layer base
	accum *= texpaint2;

	float3 color = render_target.read(tid).xyz;
	if (constant_buffer.v0.x == 0) {
		color = accum.xyz;
	}
	else {
		float a = 1.0 / constant_buffer.v0.x;
		float b = 1.0 - a;
		color = color * b + accum.xyz * a;
	}
	render_target.write(float4(color.xyz, 1.0f), tid);
}
