package arm.ui;

import haxe.io.Bytes;
import zui.Zui;
import zui.Id;
import iron.system.Input;
import iron.system.Time;
import iron.system.ArmPack;
import iron.system.Lz4;
import arm.sys.Path;
import arm.sys.File;

class UIFiles {

	public static var filename: String;
	public static var path = defaultPath;
	static var lastPath = "";
	static var lastSearch = "";
	static var files: Array<String> = null;
	static var iconMap: Map<String, kha.Image> = null;
	static var selected = -1;
	static var showExtensions = false;
	static var offline = false;

	public static function show(filters: String, isSave: Bool, openMultiple: Bool, filesDone: String->Void) {
		if (isSave) {
			path = Krom.saveDialog(filters, "");
			if (path != null) {
				while (path.indexOf(Path.sep + Path.sep) >= 0) path = path.replace(Path.sep + Path.sep, Path.sep);
				path = path.replace("\r", "");
				filename = path.substr(path.lastIndexOf(Path.sep) + 1);
				path = path.substr(0, path.lastIndexOf(Path.sep));
				filesDone(path);
			}
		}
		else {
			var paths = Krom.openDialog(filters, "", openMultiple);
			if (paths != null) {
				for (path in paths) {
					while (path.indexOf(Path.sep + Path.sep) >= 0) path = path.replace(Path.sep + Path.sep, Path.sep);
					path = path.replace("\r", "");
					filename = path.substr(path.lastIndexOf(Path.sep) + 1);
					filesDone(path);
				}
			}
		}

		releaseKeys();
	}

	// @:access(zui.Zui)
	// static function showCustom(filters: String, isSave: Bool, filesDone: String->Void) {
	// 	var known = false;
	// 	UIBox.showCustom(function(ui: Zui) {
	// 		if (ui.tab(Id.handle(), tr("File Browser"))) {
	// 			var pathHandle = Id.handle();
	// 			var fileHandle = Id.handle();
	// 			ui.row([6 / 10, 2 / 10, 2 / 10]);
	// 			filename = ui.textInput(fileHandle, tr("File"));
	// 			ui.text("*." + filters, Center);
	// 			if (ui.button(isSave ? tr("Save") : tr("Open")) || known || ui.isReturnDown) {
	// 				UIBox.hide();
	// 				filesDone((known || isSave) ? path : path + Path.sep + filename);
	// 				if (known) pathHandle.text = pathHandle.text.substr(0, pathHandle.text.lastIndexOf(Path.sep));
	// 			}
	// 			known = Path.isTexture(path) || Path.isMesh(path) || Path.isProject(path);
	// 			path = fileBrowser(ui, pathHandle, false);
	// 			if (pathHandle.changed) ui.currentWindow.redraws = 3;
	// 		}
	// 	}, 600, 500);
	// }

	static function releaseKeys() {
		// File dialog may prevent firing key up events
		var kb = kha.input.Keyboard.get();
		@:privateAccess kb.sendUpEvent(kha.input.KeyCode.Shift);
		@:privateAccess kb.sendUpEvent(kha.input.KeyCode.Control);
		#if krom_darwin
		@:privateAccess kb.sendUpEvent(kha.input.KeyCode.Meta);
		#end
	}

	@:access(zui.Zui)
	@:access(arm.sys.File)
	public static function fileBrowser(ui: Zui, handle: Handle, foldersOnly = false, dragFiles = false, search = "", refresh = false, contextMenu : String -> Void = null): String {

		var icons = Res.get("icons.k");
		var folder = Res.tile50(icons, 2, 1);
		var file = Res.tile50(icons, 3, 1);
		var isCloud = handle.text.startsWith("cloud");

		if (isCloud && File.cloud == null) File.initCloud(function() { UIBase.inst.hwnds[TabStatus].redraws = 3; });
		if (isCloud && File.readDirectory("cloud", false).length == 0) return handle.text;

		#if krom_ios
		var documentDirectory = Krom.saveDialog("", "");
		documentDirectory = documentDirectory.substr(0, documentDirectory.length - 8); // Strip /'untitled'
		#end

		if (handle.text == "") handle.text = defaultPath;
		if (handle.text != lastPath || search != lastSearch || refresh) {
			files = [];

			// Up directory
			var i1 = handle.text.indexOf(Path.sep);
			var nested = i1 > -1 && handle.text.length - 1 > i1;
			#if krom_windows
			// Server addresses like \\server are not nested
			nested = nested && !(handle.text.length >= 2 && handle.text.charAt(0) == Path.sep && handle.text.charAt(1) == Path.sep && handle.text.lastIndexOf(Path.sep) == 1);
			#end
			if (nested) files.push("..");

			var dirPath = handle.text;
			#if krom_ios
			if (!isCloud) dirPath = documentDirectory + dirPath;
			#end
			var filesAll = File.readDirectory(dirPath, foldersOnly);

			for (f in filesAll) {
				if (f == "" || f.charAt(0) == ".") continue; // Skip hidden
				if (f.indexOf(".") > 0 && !Path.isKnown(f)) continue; // Skip unknown extensions
				if (isCloud && f.indexOf("_icon.") >= 0) continue; // Skip thumbnails
				if (f.toLowerCase().indexOf(search.toLowerCase()) < 0) continue; // Search filter
				files.push(f);
			}
		}
		lastPath = handle.text;
		lastSearch = search;
		handle.changed = false;

		var slotw = Std.int(70 * ui.SCALE());
		var num = Std.int(ui._w / slotw);

		ui._y += 4; // Don't cut off the border around selected materials
		// Directory contents
		for (row in 0...Std.int(Math.ceil(files.length / num))) {

			ui.row([for (i in 0...num * 2) 1 / num]);
			if (row > 0) ui._y += ui.ELEMENT_OFFSET() * 14.0;

			for (j in 0...num) {
				var i = j + row * num;
				if (i >= files.length) {
					@:privateAccess ui.endElement(slotw);
					@:privateAccess ui.endElement(slotw);
					continue;
				}

				var f = files[i];
				var _x = ui._x;

				var rect = f.indexOf(".") > 0 ? file : folder;
				var col = rect == file ? ui.t.LABEL_COL : ui.t.LABEL_COL - 0x00202020;
				if (selected == i) col = ui.t.HIGHLIGHT_COL;

				var off = ui._w / 2 - 25 * ui.SCALE();
				ui._x += off;

				var uix = ui._x;
				var uiy = ui._y;
				var state = Idle;
				var generic = true;
				var icon: kha.Image = null;

				if (isCloud && f != ".." && !offline) {
					if (iconMap == null) iconMap = [];
					icon = iconMap.get(handle.text + Path.sep + f);
					if (icon == null) {
						var filesAll = File.readDirectory(handle.text);
						var iconFile = f.substr(0, f.lastIndexOf(".")) + "_icon.jpg";
						if (filesAll.indexOf(iconFile) >= 0) {
							var empty = iron.RenderPath.active.renderTargets.get("empty_black").image;
							iconMap.set(handle.text + Path.sep + f, empty);
							File.cacheCloud(handle.text + Path.sep + iconFile, function(abs: String) {
								if (abs != null) {
									iron.data.Data.getImage(abs, function(image: kha.Image) {
										iron.App.notifyOnInit(function() {
											if (App.pipeCopyRGB == null) App.makePipeCopyRGB();
											icon = kha.Image.createRenderTarget(image.width, image.height);
											if (f.endsWith(".arm")) { // Used for material sphere alpha cutout
												icon.g2.begin(false);

												#if (is_paint || is_sculpt)
												icon.g2.drawImage(Project.materials[0].image, 0, 0);
												#end
											}
											else {
												icon.g2.begin(true, 0xffffffff);
											}
											icon.g2.pipeline = App.pipeCopyRGB;
											icon.g2.drawImage(image, 0, 0);
											icon.g2.pipeline = null;
											icon.g2.end();
											iconMap.set(handle.text + Path.sep + f, icon);
											UIBase.inst.hwnds[TabStatus].redraws = 3;
										});
									});
								}
								else offline = true;
							});
						}
					}
					if (icon != null) {
						var w = 50;
						if (i == selected) {
							ui.fill(-2,        -2, w + 4,     2, ui.t.HIGHLIGHT_COL);
							ui.fill(-2,     w + 2, w + 4,     2, ui.t.HIGHLIGHT_COL);
							ui.fill(-2,         0,     2, w + 4, ui.t.HIGHLIGHT_COL);
							ui.fill(w + 2 ,    -2,     2, w + 6, ui.t.HIGHLIGHT_COL);
						}
						state = ui.image(icon, 0xffffffff, w * ui.SCALE());
						if (ui.isHovered) {
							ui.tooltipImage(icon);
							ui.tooltip(f);
						}
						generic = false;
					}
				}
				if (f.endsWith(".arm") && !isCloud) {
					if (iconMap == null) iconMap = [];
					var key = handle.text + Path.sep + f;
					icon = iconMap.get(key);
					if (!iconMap.exists(key)) {
						var blobPath = key;

						#if krom_ios
						blobPath = documentDirectory + blobPath;
						// TODO: implement native .arm parsing first
						#else

						var bytes = Bytes.ofData(Krom.loadBlob(blobPath));
						var raw = ArmPack.decode(bytes);
						if (raw.material_icons != null) {
							var bytesIcon = raw.material_icons[0];
							icon = kha.Image.fromBytes(Lz4.decode(bytesIcon, 256 * 256 * 4), 256, 256);
						}

						#if (is_paint || is_sculpt)
						else if (raw.mesh_icons != null) {
							var bytesIcon = raw.mesh_icons[0];
							icon = kha.Image.fromBytes(Lz4.decode(bytesIcon, 256 * 256 * 4), 256, 256);
						}
						else if (raw.brush_icons != null) {
							var bytesIcon = raw.brush_icons[0];
							icon = kha.Image.fromBytes(Lz4.decode(bytesIcon, 256 * 256 * 4), 256, 256);
						}
						#end

						#if is_lab
						if (raw.mesh_icon != null) {
							var bytesIcon = raw.mesh_icon;
							icon = kha.Image.fromBytes(Lz4.decode(bytesIcon, 256 * 256 * 4), 256, 256);
						}
						#end

						iconMap.set(key, icon);
						#end
					}
					if (icon != null) {
						var w = 50;
						if (i == selected) {
							ui.fill(-2,        -2, w + 4,     2, ui.t.HIGHLIGHT_COL);
							ui.fill(-2,     w + 2, w + 4,     2, ui.t.HIGHLIGHT_COL);
							ui.fill(-2,         0,     2, w + 4, ui.t.HIGHLIGHT_COL);
							ui.fill(w + 2 ,    -2,     2, w + 6, ui.t.HIGHLIGHT_COL);
						}
						state = ui.image(icon, 0xffffffff, w * ui.SCALE());
						if (ui.isHovered) {
							ui.tooltipImage(icon);
							ui.tooltip(f);
						}
						generic = false;
					}
				}

				if (Path.isTexture(f) && !isCloud) {
					var w = 50;
					if (iconMap == null) iconMap = [];
					icon = iconMap.get(handle.text + Path.sep + f);
					if (icon == null) {
						var empty = iron.RenderPath.active.renderTargets.get("empty_black").image;
						iconMap.set(handle.text + Path.sep + f, empty);
						kha.Assets.loadImageFromPath(handle.text + Path.sep + f, false, function(image: kha.Image) {
							iron.App.notifyOnInit(function() {
								if (App.pipeCopyRGB == null) App.makePipeCopyRGB();
								var sw = image.width > image.height ? w : Std.int(1.0 * image.width / image.height * w);
								var sh = image.width > image.height ? Std.int(1.0 * image.height / image.width * w) : w;
								icon = kha.Image.createRenderTarget(sw, sh);
								icon.g2.begin(true, 0xffffffff);
								icon.g2.pipeline = App.pipeCopyRGB;
								icon.g2.drawScaledImage(image, 0, 0, sw, sh);
								icon.g2.pipeline = null;
								icon.g2.end();
								iconMap.set(handle.text + Path.sep + f, icon);
								UIBase.inst.hwnds[TabStatus].redraws = 3;
								image.unload(); // The big image is not needed anymore
							});
						});
					}
					if (icon != null) {
						if (i == selected) {
							ui.fill(-2,        -2, w + 4,     2, ui.t.HIGHLIGHT_COL);
							ui.fill(-2,     w + 2, w + 4,     2, ui.t.HIGHLIGHT_COL);
							ui.fill(-2,         0,     2, w + 4, ui.t.HIGHLIGHT_COL);
							ui.fill(w + 2 ,    -2,     2, w + 6, ui.t.HIGHLIGHT_COL);
						}
						state = ui.image(icon, 0xffffffff, icon.height * ui.SCALE());
						generic = false;
					}
				}

				if (generic) {
					state = ui.image(icons, col, 50 * ui.SCALE(), rect.x, rect.y, rect.w, rect.h);
				}

				if (ui.isHovered && ui.inputReleasedR && contextMenu != null) {
					contextMenu(handle.text + Path.sep + f);
				}

				if (state == Started) {
					if (f != ".." && dragFiles) {
						var mouse = Input.getMouse();
						App.dragOffX = -(mouse.x - uix - ui._windowX - 3);
						App.dragOffY = -(mouse.y - uiy - ui._windowY + 1);
						App.dragFile = handle.text;
						#if krom_ios
						if (!isCloud) App.dragFile = documentDirectory + App.dragFile;
						#end
						if (App.dragFile.charAt(App.dragFile.length - 1) != Path.sep) {
							App.dragFile += Path.sep;
						}
						App.dragFile += f;
						App.dragFileIcon = icon;
					}

					selected = i;
					if (Time.time() - Context.raw.selectTime < 0.25) {
						App.dragFile = null;
						App.dragFileIcon = null;
						App.isDragging = false;
						handle.changed = ui.changed = true;
						if (f == "..") { // Up
							handle.text = handle.text.substring(0, handle.text.lastIndexOf(Path.sep));
							// Drive root
							if (handle.text.length == 2 && handle.text.charAt(1) == ":") handle.text += Path.sep;
						}
						else {
							if (handle.text.charAt(handle.text.length - 1) != Path.sep) {
								handle.text += Path.sep;
							}
							handle.text += f;
						}
						selected = -1;
					}
					Context.raw.selectTime = Time.time();
				}

				// Label
				ui._x = _x;
				ui._y += slotw * 0.75;
				var label0 = (showExtensions || f.indexOf(".") <= 0) ? f : f.substr(0, f.lastIndexOf("."));
				var label1 = "";
				while (label0.length > 0 && ui.ops.font.width(ui.fontSize, label0) > ui._w - 6) { // 2 line split
					label1 = label0.charAt(label0.length - 1) + label1;
					label0 = label0.substr(0, label0.length - 1);
				}
				if (label1 != "") ui.curRatio--;
				ui.text(label0, Center);
				if (ui.isHovered) ui.tooltip(label0 + label1);
				if (label1 != "") { // Second line
					ui._x = _x;
					ui._y += ui.ops.font.height(ui.fontSize);
					ui.text(label1, Center);
					if (ui.isHovered) ui.tooltip(label0 + label1);
					ui._y -= ui.ops.font.height(ui.fontSize);
				}

				ui._y -= slotw * 0.75;

				if (handle.changed) break;
			}

			if (handle.changed) break;
		}
		ui._y += slotw * 0.8;

		return handle.text;
	}

	public static inline var defaultPath =
		#if krom_windows
		"C:\\Users"
		#elseif krom_android
		"/storage/emulated/0/Download"
		#elseif krom_darwin
		"/Users"
		#else
		"/"
		#end
	;
}
