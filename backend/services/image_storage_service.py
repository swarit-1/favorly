"""
Image storage service for uploading images.

For development: saves to local filesystem.
For production: should use Supabase Storage or cloud provider.
"""

import os
import shutil
from pathlib import Path
from fastapi import UploadFile
from typing import List
from datetime import datetime
import logging

logger = logging.getLogger(__name__)


class ImageStorageService:
    """Handle image uploads (local development, cloud for production)"""

    def __init__(self):
        # Development: save to local temp directory
        self.upload_dir = Path("/tmp/favorly_images")
        self.upload_dir.mkdir(parents=True, exist_ok=True)
        logger.info(f"📁 Image storage initialized: {self.upload_dir}")

        # For production: would initialize Supabase or cloud storage
        # self.supabase_url = os.getenv("SUPABASE_URL")
        # self.supabase_key = os.getenv("SUPABASE_KEY")
        # self.bucket_name = "vision-uploads"

    async def upload_image(
        self,
        file: UploadFile,
        user_id: str,
        domain: str,
    ) -> str:
        """
        Upload single image and save to disk

        Returns: Absolute path to saved image
        """
        try:
            # Create directory structure
            timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
            dir_path = self.upload_dir / domain / user_id / timestamp
            dir_path.mkdir(parents=True, exist_ok=True)

            # Save the file
            filename = file.filename or "image.jpg"
            file_path = dir_path / filename

            # Read and save file content
            contents = await file.read()
            with open(file_path, "wb") as f:
                f.write(contents)

            logger.info(f"✅ Image saved: {file_path} ({len(contents)} bytes)")
            return str(file_path)

        except Exception as e:
            logger.error(f"❌ Error uploading image: {e}")
            raise

    async def upload_images(
        self,
        files: List[UploadFile],
        user_id: str,
        domain: str,
    ) -> List[str]:
        """Upload multiple images to same directory"""
        paths = []
        for file in files:
            path = await self.upload_image(file, user_id, domain)
            paths.append(path)
        logger.info(f"📤 Uploaded {len(paths)} images")
        return paths

    def get_image_url(self, path: str) -> str:
        """Get URL for local image (development only)"""
        # For development, return local path
        # For production, would return cloud storage URL
        return f"file://{path}"

    async def delete_image(self, path: str) -> bool:
        """Delete image from local storage"""
        try:
            if os.path.exists(path):
                os.remove(path)
                logger.info(f"🗑️  Deleted: {path}")
                return True
            return False
        except Exception as e:
            logger.error(f"❌ Error deleting image: {e}")
            return False
