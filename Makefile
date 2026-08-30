ZIG    ?= zig
GAMES   = minimal vecpong veclander vecinvaders vectetris vecblackhole

# Build the vgame platform library.
build:
	$(ZIG) build

# Build every sample game.
build-samples:
	@for game in $(GAMES); do \
		echo "==> Building $$game..."; \
		(cd examples/$$game && $(ZIG) build) || exit 1; \
	done

# Build all samples with release optimization.
build-samples-release:
	@for game in $(GAMES); do \
		echo "==> Building $$game (release)..."; \
		(cd examples/$$game && $(ZIG) build --release=fast) || exit 1; \
	done

# Build a single sample. Usage: make build-sample GAME=vecpong
build-sample:
	@test -n "$(GAME)" || { echo "Usage: make build-sample GAME=<name>"; exit 1; }
	cd examples/$(GAME) && $(ZIG) build

# Run a sample game. Usage: make run-sample GAME=vecpong
run-sample:
	@test -n "$(GAME)" || { echo "Usage: make run-sample GAME=<name>"; exit 1; }
	cd examples/$(GAME) && $(ZIG) build run

# Convenience targets for each game.
run-minimal:
	cd examples/minimal && $(ZIG) build run

run-vecpong:
	cd examples/vecpong && $(ZIG) build run

run-veclander:
	cd examples/veclander && $(ZIG) build run

run-vecinvaders:
	cd examples/vecinvaders && $(ZIG) build run

run-vectetris:
	cd examples/vectetris && $(ZIG) build run

run-vecblackhole:
	cd examples/vecblackhole && $(ZIG) build run

# Install system dependencies for raylib (Fedora).
deps:
	sudo dnf install -y \
	    glfw-devel \
	    mesa-libGL-devel \
	    mesa-libGLU-devel \
	    libX11-devel \
	    libXrandr-devel \
	    libXinerama-devel \
	    libXi-devel \
	    libXcursor-devel \
	    libxcrypt-compat \
	    alsa-lib-devel \
	    pulseaudio-libs-devel

# Pin to glibc 2.42 (Bazzite's glibc version) so the binary built on this
# (newer-glibc) host doesn't fail on Bazzite with a GLIBC_x.xx not found
# error.
build-bazzite:
	$(ZIG) build -Dtarget=x86_64-linux-gnu.2.42 -Dsysroot=/

# Cross-compile a sample for Raspberry Pi (Wayland + GLES 3).
# Usage: make build-pi GAME=vecpong
build-pi:
	@test -n "$(GAME)" || { echo "Usage: make build-pi GAME=<name>"; exit 1; }
	cd examples/$(GAME) && $(ZIG) build \
	    -Dtarget=aarch64-linux-gnu \
	    -Dlinux_display_backend=wayland \
	    -Dopengl_version=gles_3 \
	    --release=fast

# List available sample games.
list-samples:
	@echo "Available sample games:"
	@for game in $(GAMES); do \
		echo "  $$game  (make run-$$game  or  make run-sample GAME=$$game)"; \
	done

# Print help for all targets.
help:
	@echo "vgame — Vector Game Platform"
	@echo ""
	@echo "Build targets:"
	@echo "  make build                  Build the vgame platform library"
	@echo "  make build-samples           Build all 6 sample games"
	@echo "  make build-samples-release   Build all samples with --release=fast"
	@echo "  make build-sample GAME=<name> Build one game"
	@echo "  make build-bazzite           Cross-compile for Bazzite glibc 2.42"
	@echo "  make build-pi GAME=<name>     Cross-compile for Raspberry Pi (Wayland + GLES 3)"
	@echo ""
	@echo "Run targets:"
	@echo "  make run-sample GAME=<name>  Build and run any game by name"
	@echo "  make run-minimal             Build and run the minimal example"
	@echo "  make run-vecpong             Build and run VecPong"
	@echo "  make run-veclander           Build and run VecLander"
	@echo "  make run-vecinvaders         Build and run VecInvaders"
	@echo "  make run-vectetris           Build and run VecTetris"
	@echo "  make run-vecblackhole        Build and run VecBlackhole"
	@echo ""
	@echo "Other targets:"
	@echo "  make list-samples            List available sample games"
	@echo "  make deps                    Install Fedora system dependencies for raylib"
	@echo "  make clean                   Remove all build outputs and caches"
	@echo "  make help                    Show this help message"
	@echo ""
	@echo "Sample games: $(GAMES)"
	@echo ""
	@echo "Usage examples:"
	@echo "  make build-samples           # build everything"
	@echo "  make run-vecpong             # play pong"
	@echo "  make run-sample GAME=vectetris  # play tetris"
	@echo "  make build-pi GAME=vecpong   # cross-compile pong for Raspberry Pi"

# Remove all build outputs and caches.
clean:
	rm -rf zig-out .zig-cache
	@for game in $(GAMES); do \
		rm -rf examples/$$game/zig-out examples/$$game/.zig-cache; \
	done

.PHONY: build build-samples build-samples-release build-sample run-sample \
         run-minimal run-vecpong run-veclander run-vecinvaders run-vectetris run-vecblackhole \
         deps build-bazzite build-pi clean list-samples help