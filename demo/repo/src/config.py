"""Configuration loader for Lab Agent."""

import os
from pathlib import Path


def load_config():
    """Load configuration from environment and .env file."""
    env_path = Path(__file__).parent.parent / ".env"
    config = {"app_name": "lab-agent"}

    if env_path.exists():
        # In production, use python-dotenv. For demo, simple parse.
        for line in env_path.read_text().splitlines():
            if "=" in line and not line.startswith("#"):
                key, _, value = line.partition("=")
                config[key.strip()] = value.strip()

    return config
