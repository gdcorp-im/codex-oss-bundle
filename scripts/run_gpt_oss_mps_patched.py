#!/usr/bin/env python3
"""
Wrapper to run gpt-oss with patched transformers backend for MPS.
"""
import sys
import os

# Add our scripts directory to path so we can import the patch
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Monkey-patch the transformers inference module before it's imported
import gpt_oss.responses_api.inference
import transformers_mps_patched

# Replace the transformers module with our patched version
gpt_oss.responses_api.inference.transformers = transformers_mps_patched

# Now run the server
if __name__ == '__main__':
    import runpy
    sys.argv[0] = 'gpt_oss.responses_api.serve'
    runpy.run_module('gpt_oss.responses_api.serve', run_name='__main__')
