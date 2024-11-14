default:
	@echo "Usage: make [clean|release]"
clean:
	@echo "Cleaning AP"
	@${MAKE} -C c/ clean
	@rm -rf build
release:
	@echo "Building release firmware"
	@cd ../ && zig build component
	@${MAKE} -C c/ release
	@mkdir -p build
	@cp c/build/max78000.elf build/
	@cp c/build/max78000.bin build/
