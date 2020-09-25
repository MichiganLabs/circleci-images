BUNDLES = \
  android node

images: $(foreach b, $(BUNDLES), $(b)/generate_images)

%/generate_images:
	cd $(@D) && ./generate-images

example_images: $(foreach b, $(BUNDLES), $(b)/example_images)

%/example_images:
	./shared/images/example.sh $(@D)

publish_images: images
	find . -name Dockerfile | awk '{ print length, $0 }' | sort -n -s | cut -d" " -f2- | sed 's|/Dockerfile|/publish_image|g' | xargs -n1 make

%/publish_images: %/generate_images
	find ./$(@D) -name Dockerfile | awk '{ print length, $$0 }' | sort -n -s | cut -d" " -f2- | sed 's|/Dockerfile|/publish_image|g' | xargs -n1 make

%/publish_image: %/Dockerfile
	./shared/images/build.sh ./$(@D)/Dockerfile

clean: $(foreach b, $(BUNDLES), $(b)/clean)

%/clean:
	cd $(@D) ; rm -r images || true

list_bundles: $(foreach b, $(BUNDLES), $(b)/echo_bundle)

%/echo_bundle:
	echo $(@D) >> BUNDLES.txt
