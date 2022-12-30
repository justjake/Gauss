PROJECT:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
GIT_CLONE_SPARSE=GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1

# can be original or split_einsum
ATTENTION_TYPE=original
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

.PHONY: download zips clean clean-all

download: compiled-models/sd1.4 compiled-models/sd1.5 compiled-models/sd2
zips: compiled-models/sd1.4.zip.00 compiled-models/sd1.5.zip.00 compiled-models/sd2.zip.00

clean:
	@echo "Note: run 'make clean-all' to remove downloaded repos, which are large"
	rm -rf compiled-models/*.zip*
	find compiled-models -maxdepth 1 -type l -delete

clean-all:
	rm -rf compiled-models

# Targets to clone each model's repo from HuggingFace,
# then hydrate the large files we care about using `git lfs`
compiled-models/sd1.4.repo:
	$(GIT_CLONE_SPARSE) https://huggingface.co/apple/coreml-stable-diffusion-v1-4 $@
	@make $@.checkout

compiled-models/sd1.5.repo:
	$(GIT_CLONE_SPARSE) https://huggingface.co/apple/coreml-stable-diffusion-v1-5 $@
	@make $@.checkout

compiled-models/sd2.repo:
	$(GIT_CLONE_SPARSE) https://huggingface.co/apple/coreml-stable-diffusion-2-base $@
	@make $@.checkout

compiled-models/%.repo.checkout: compiled-models/%.repo
	cd $^ && git lfs fetch --include $(MODEL_SPARSE_CHECKOUT_PATTERN)
	cd $^ && git lfs checkout $(MODEL_SPARSE_CHECKOUT_FILES)

# Make a symlink directly to the subdirectory of the repo that contains the
# models we want to use.
#
# This makes it easier to build a zip with the paths we want.
compiled-models/%: compiled-models/%.repo
	ln -sf $(PROJECT)/$^/$(MODEL_REPO_PATH) $@

# Zip directories
compiled-models/%.zip: compiled-models/%
	cd compiled-models && zip -r $(notdir $@) $(notdir $^)/

# Split zips into 1900 MB chunks
compiled-models/%.zip.00: compiled-models/%.zip
	split -b 1900m -d $^ $^.

# Please don't remove intermediate files
.SECONDARY:
