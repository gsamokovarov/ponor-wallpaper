NAME ?= ponor-brush

LIGHT := src/$(NAME)/light.png
DARK  := src/$(NAME)/dark.png
HEIC  := dist/$(NAME).heic

PREVIEW := preview.jpg
PREVIEW_WIDTH := 1280
PREVIEW_QUALITY := 85

.PHONY: all preview clean

all: $(HEIC)

$(HEIC): $(LIGHT) $(DARK) build.sh
	./build.sh $(NAME)

preview: $(PREVIEW)

# Left half from light.png, right half from dark.png, downscaled and optimized
# for the README. -crop 50%x100% splits each source in two; -delete keeps the
# half we want before +append stitches them back together.
$(PREVIEW): $(LIGHT) $(DARK)
	magick \
	  \( $(LIGHT) -crop 50%x100% +repage -delete 1 \) \
	  \( $(DARK)  -crop 50%x100% +repage -delete 0 \) \
	  +append \
	  -resize $(PREVIEW_WIDTH)x \
	  -strip \
	  -interlace Plane \
	  -sampling-factor 4:2:0 \
	  -quality $(PREVIEW_QUALITY) \
	  $@

clean:
	rm -rf dist
