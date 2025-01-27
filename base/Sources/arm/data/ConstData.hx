package arm.data;

import kha.graphics4.TextureFormat;
import kha.Blob;
import kha.Image;
import iron.data.Data;
import iron.system.ArmPack;

class ConstData {
	#if arm_ltc
	public static var ltcMatTex: Image = null;
	public static var ltcMagTex: Image = null;
	public static function initLTC() {
		// Real-Time Polygonal-Light Shading with Linearly Transformed Cosines
		// https://eheitzresearch.wordpress.com/415-2/
		Data.getBlob("ltc_mat.arm", function(ltc_mat: Blob) {
			Data.getBlob("ltc_mag.arm", function(ltc_mag: Blob) {
				ltcMatTex = Image.fromBytes(ArmPack.decode(ltc_mat.toBytes()), 64, 64, TextureFormat.RGBA128);
				ltcMagTex = Image.fromBytes(ArmPack.decode(ltc_mag.toBytes()), 64, 64, TextureFormat.A32);
			});
		});
	}
	#end
}
