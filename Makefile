PROJECT:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
GIT_CLONE_SPARSE=GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1

ATTENTION_TYPE=original # or split_einsum
MODEL_REPO_PATH=$(ATTENTION_TYPE)/compiled
MODEL_FILES=
MODEL_FILES+=SafetyChecker.mlmodelc
MODEL_FILES+=TextEncoder.mlmodelc
MODEL_FILES+=VAEDecoder.mlmodelc
MODEL_FILES+=merges.txt
MODEL_FILES+=vocab.json
ifeq ($(ATTENTION_TYPE),split_einsum)
	# If we target iOS, we need to use chunked Unet, which is only available
	# with MODEL_REPO_PATH `split_einsum/compiled`.
MODEL_FILES+=UnetChunk1.mlmodelc
MODEL_FILES+=UnetChunk2.mlmodelc
else
MODEL_FILES+=Unet.mlmodelc
endif

MODEL_SPARSE_CHECKOUT_FILES=$(addprefix $(MODEL_REPO_PATH)/,$(MODEL_FILES))
MODEL_SPARSE_CHECKOUT_PATTERNS=$(MODEL_SPARSE_CHECKOUT_FILES)
SPACE:=$(subst ,, )
COMMA:=,
MODEL_SPARSE_CHECKOUT_PATTERN=$(subst $(SPACE),$(COMMA),$(MODEL_SPARSE_CHECKOUT_PATTERNS))

.PHONY: download zips clean

download: compiled-models/sd1.4 compiled-models/sd1.5 compiled-models/sd2
zips: compiled-models/sd1.4.zip.00 compiled-models/sd1.5.zip.00 compiled-models/sd2.zip.00

clean:
	rm -rf compiled-models/*.zip*
	@echo "Not removing repos since they take many GB to download, delete manually"

compiled-models/sd1.4.repo:
	$(GIT_CLONE_SPARSE) https://huggingface.co/apple/coreml-stable-diffusion-v1-4 $@
	cd $@ && git lfs fetch --include $(MODEL_SPARSE_CHECKOUT_PATTERN)

compiled-models/sd1.5.repo:
	$(GIT_CLONE_SPARSE) https://huggingface.co/apple/coreml-stable-diffusion-v1-5 $@
	cd $@ && git lfs fetch --include $(MODEL_SPARSE_CHECKOUT_PATTERN)

compiled-models/sd2.repo:
	$(GIT_CLONE_SPARSE) https://huggingface.co/apple/coreml-stable-diffusion-2-base $@
	cd $@ && git lfs fetch --include $(MODEL_SPARSE_CHECKOUT_PATTERN)

compiled-models/%: compiled-models/%.repo
	ln -s $(PROJECT)/$^/$(MODEL_REPO_PATH) $@

# Zip directories
%.zip: compiled-models/%
	zip -r $@ $^/

# Split zips into 1900 MB chunks
%.zip.00: %.zip
	split -b 1900m -d $^ $^.
