default:
	@echo "Usage: make [clean|release]"
clean:
	@echo "Cleaning Decoder"
	@${MAKE} -C c/ clean
	@rm -rf build
release:
	@echo "Building release firmware"
	@zig build decoder
	@${MAKE} -C c/ release
	@mkdir -p /out
	@cp c/build/max78000.elf /out/
	@cp c/build/max78000.bin /out/
