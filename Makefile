# Use bash instead of sh
SHELL := /bin/bash

# Docker image & model path
IMAGE = llama
IMAGE_DEV = llama-dev
MODELS_PATH = $(HOME)/models
MODEL_DIR = Qwen3-8B-GPT-5-Reasoning-Distill
MODEL_FILE = Qwen3-8B-GPT-5-Reasoning-Distill.F16.gguf
MODEL_Q6_FILE = Qwen3-8B-GPT-5-Reasoning-Distill.Q6_K.gguf
MODEL_URL = https://huggingface.co/Liontix/Qwen3-8B-GPT-5-Reasoning-Distill-Safetensors/resolve/main
DOCKER_RUN_PROD = docker run -p 60999:8080 --gpus all --cap-add=IPC_LOCK --ulimit memlock=-1:-1 --rm -v $(MODELS_PATH):/models $(IMAGE) bash -c
DOCKER_RUN_DEV = docker run -it --rm -v $(MODELS_PATH):/models $(IMAGE_DEV) bash -c

# ----------------------------------------
# Docker Build
# ----------------------------------------

# Build production image
build:
	docker build -t $(IMAGE) .

# Build development image (for HF → GGUF conversion)
build-dev:
	docker build -f Dockerfile.dev -t $(IMAGE_DEV) .

# ----------------------------------------
# Cases
# ----------------------------------------

# 共通実行コマンド
RUN_CMD = llama-server --host 0.0.0.0 -m /models/$(MODEL_DIR)/$(MODEL_FILE) --no-mmap --ctx-size 8192

# Case A
download-model:
	@mkdir -p $(MODELS_PATH)/$(MODEL_DIR)
	wget $(MODEL_URL) -O $(MODELS_PATH)/$(MODEL_DIR)/$(MODEL_FILE)

run:
	$(DOCKER_RUN_PROD) "$(RUN_CMD) \
		--override-tensor 'blk\.4[0-9]\.ffn_down\.weight=CPU' \
		--override-tensor 'blk\.3[3-9]\.ffn_down\.weight=CPU' \
		--override-tensor 'blk\.4[0-9]\.ffn_gate\.weight=CPU' \
		--override-tensor 'blk\.3[3-9]\.ffn_gate\.weight=CPU' \
		--override-tensor 'blk\.4[0-9]\.ffn_up\.weight=CPU' \
		--override-tensor 'blk\.3[3-9]\.ffn_up\.weight=CPU'"

dev-shell:
	$(DOCKER_RUN_DEV) bash

# Download safetensors files
download-safetensors:
	@mkdir -p $(MODELS_PATH)/$(MODEL_DIR)
	cd $(MODELS_PATH)/$(MODEL_DIR)
	wget $(MODEL_URL)/model.safetensors -O model.safetensors
	wget $(MODEL_URL)/tokenizer.json -O tokenizer.json
	wget $(MODEL_URL)/config.json -O config.json
	wget $(MODEL_URL)/tokenizer_config.json -O tokenizer_config.json
	wget $(MODEL_URL)/special_tokens_map.json -O special_tokens_map.json

# 変換コマンド
convert-to-gguf: download-safetensors
	$(DOCKER_RUN_DEV) "cd /workspace/llama.cpp && python3 convert.py /models/$(MODEL_DIR) --outtype f16 --output /models/$(MODEL_DIR)/$(MODEL_FILE)"

# Quantize model to Q6_K using llama.cpp
quantize-q6:
	$(DOCKER_RUN_PROD) "llama-quantize /models/$(MODEL_DIR)/$(MODEL_FILE) /models/$(MODEL_DIR)/$(MODEL_Q6_FILE) Q6_K"

# Run with Q6_K quantized model
run-q6:
	$(DOCKER_RUN_PROD) "$(RUN_CMD) -m /models/$(MODEL_DIR)/$(MODEL_Q6_FILE)"


.PHONY: build download-model convert-to-gguf run quantize-q6 run-q6