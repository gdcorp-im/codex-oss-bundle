#!/usr/bin/env python3
"""
Wrapper to force gpt-oss to run on CPU by monkey-patching torch before model loads.
"""
import sys
import os

# Force CPU before any torch imports
os.environ['PYTORCH_ENABLE_MPS_FALLBACK'] = '0'
os.environ['CUDA_VISIBLE_DEVICES'] = ''

# Monkey-patch torch.backends.mps to report as unavailable BEFORE importing torch
import sys
import importlib.util
spec = importlib.util.find_spec('torch')
if spec:
    import torch.backends.mps
    torch.backends.mps.is_available = lambda: False
    torch.backends.mps.is_built = lambda: False

# Now run the server module as __main__
if __name__ == '__main__':
    import runpy
    sys.argv[0] = 'gpt_oss.responses_api.serve'
    runpy.run_module('gpt_oss.responses_api.serve', run_name='__main__')
