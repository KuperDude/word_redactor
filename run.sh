#!/bin/bash
docker run -it --rm -v "$(pwd)":/app -w /app docx-live-arch ./scripts/docx_live_controller.sh
