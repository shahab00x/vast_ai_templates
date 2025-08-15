#!/bin/bash
set -e

echo "=== Starting Flux Kontext Setup ==="

# Ensure we're in the right directory
cd /workspace/ComfyUI

echo "Creating model directories..."
mkdir -p models/unet
mkdir -p models/vae 
mkdir -p models/clip
mkdir -p custom_nodes

echo "Downloading Flux Kontext model (this will take several minutes)..."
cd models/unet
if [ ! -f "flux-kontext-dev.safetensors" ]; then
    wget -q --show-progress -O flux-kontext-dev.safetensors \
    "https://huggingface.co/black-forest-labs/FLUX.1-Kontext-dev/resolve/main/flux-kontext-dev.safetensors"
    echo "✓ Flux Kontext model downloaded"
else
    echo "✓ Flux Kontext model already exists"
fi

echo "Downloading VAE model..."
cd ../vae
if [ ! -f "ae.safetensors" ]; then
    wget -q --show-progress -O ae.safetensors \
    "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors"
    echo "✓ VAE model downloaded"
else
    echo "✓ VAE model already exists"
fi

echo "Downloading text encoders..."
cd ../clip
if [ ! -f "clip_l.safetensors" ]; then
    wget -q --show-progress -O clip_l.safetensors \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors"
    echo "✓ CLIP-L downloaded"
else
    echo "✓ CLIP-L already exists"
fi

if [ ! -f "t5xxl_fp16.safetensors" ]; then
    wget -q --show-progress -O t5xxl_fp16.safetensors \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors"
    echo "✓ T5-XXL downloaded"
else
    echo "✓ T5-XXL already exists"
fi

echo "Installing essential custom nodes..."
cd /workspace/ComfyUI/custom_nodes

# ComfyUI Manager for easy node management
if [ ! -d "ComfyUI-Manager" ]; then
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git
    echo "✓ ComfyUI Manager installed"
fi

# Essential nodes for Flux
if [ ! -d "ComfyUI_essentials" ]; then
    git clone --depth 1 https://github.com/cubiq/ComfyUI_essentials.git
    echo "✓ ComfyUI Essentials installed"
fi

# Flux-specific nodes
if [ ! -d "ComfyUI-FluxTrainer" ]; then
    git clone --depth 1 https://github.com/kijai/ComfyUI-FluxTrainer.git
    echo "✓ Flux Trainer nodes installed"
fi

echo "Installing Python dependencies for custom nodes..."
cd /workspace/ComfyUI
pip install -q opencv-python pillow numpy

# Create a basic Flux Kontext workflow
echo "Creating sample workflow..."
cat > /workspace/ComfyUI/flux_kontext_workflow.json << 'EOF'
{
  "1": {
    "inputs": {
      "image": "your_input_image.jpg",
      "upload": "image"
    },
    "class_type": "LoadImage",
    "_meta": {
      "title": "Load Image"
    }
  },
  "2": {
    "inputs": {
      "text": "Change the sky to sunset colors",
      "clip": ["7", 0]
    },
    "class_type": "CLIPTextEncode",
    "_meta": {
      "title": "CLIP Text Encode (Prompt)"
    }
  },
  "3": {
    "inputs": {
      "seed": 42,
      "steps": 20,
      "cfg": 7.0,
      "sampler_name": "euler",
      "scheduler": "normal",
      "denoise": 0.8,
      "model": ["6", 0],
      "positive": ["2", 0],
      "negative": ["8", 0],
      "latent_image": ["5", 0]
    },
    "class_type": "KSampler",
    "_meta": {
      "title": "KSampler"
    }
  },
  "4": {
    "inputs": {
      "samples": ["3", 0],
      "vae": ["9", 0]
    },
    "class_type": "VAEDecode",
    "_meta": {
      "title": "VAE Decode"
    }
  },
  "5": {
    "inputs": {
      "pixels": ["1", 0],
      "vae": ["9", 0]
    },
    "class_type": "VAEEncode",
    "_meta": {
      "title": "VAE Encode"
    }
  },
  "6": {
    "inputs": {
      "unet_name": "flux-kontext-dev.safetensors"
    },
    "class_type": "UNETLoader",
    "_meta": {
      "title": "Load Flux Kontext Model"
    }
  },
  "7": {
    "inputs": {
      "clip_name1": "clip_l.safetensors",
      "clip_name2": "t5xxl_fp16.safetensors"
    },
    "class_type": "DualCLIPLoader",
    "_meta": {
      "title": "DualCLIPLoader"
    }
  },
  "8": {
    "inputs": {
      "text": "",
      "clip": ["7", 0]
    },
    "class_type": "CLIPTextEncode",
    "_meta": {
      "title": "CLIP Text Encode (Negative)"
    }
  },
  "9": {
    "inputs": {
      "vae_name": "ae.safetensors"
    },
    "class_type": "VAELoader",
    "_meta": {
      "title": "Load VAE"
    }
  },
  "10": {
    "inputs": {
      "filename_prefix": "flux_kontext_output",
      "images": ["4", 0]
    },
    "class_type": "SaveImage",
    "_meta": {
      "title": "Save Image"
    }
  }
}
EOF

echo "Creating startup script..."
cat > /workspace/start_comfyui.sh << 'EOF'
#!/bin/bash
echo "=== Starting ComfyUI with Flux Kontext ==="
echo "ComfyUI will be available at: http://localhost:8188"
echo "GPU Memory: $(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits) MB"
echo "Models loaded and ready!"
echo ""

cd /workspace/ComfyUI
python main.py --listen 0.0.0.0 --port 8188 --preview-method auto
EOF

chmod +x /workspace/start_comfyui.sh

echo ""
echo "=== Flux Kontext Setup Complete! ==="
echo "✓ All models downloaded and ready"
echo "✓ Custom nodes installed"  
echo "✓ Sample workflow created"
echo "✓ Ready to start ComfyUI"
echo ""
echo "To start: /workspace/start_comfyui.sh"
echo "Or ComfyUI will auto-start if using the template correctly"
echo ""

exec bash /workspace/start_comfyui.sh

EOF
