"""
Image storage service for uploading to Supabase Storage.
"""

import os
from fastapi import UploadFile
from typing import List
from datetime import datetime
import logging

logger = logging.getLogger(__name__)


class ImageStorageService:
    """Handle image uploads to Supabase Storage"""

    def __init__(self):
        self.supabase_url = os.getenv("SUPABASE_URL")
        self.supabase_key = os.getenv("SUPABASE_KEY")
        self.bucket_name = "vision-uploads"  # Will be created if doesn't exist

        # TODO: Initialize Supabase client when implementing real storage
        # from supabase import create_client
        # self.supabase = create_client(self.supabase_url, self.supabase_key)

    async def upload_image(
        self,
        file: UploadFile,
        user_id: str,
        domain: str,
    ) -> str:
        """
        Upload single image to Supabase Storage

        Returns: Path/URL of uploaded image
        """
        try:
            # TODO: Implement real Supabase upload
            # For now, return a mock path
            timestamp = datetime.utcnow().isoformat()
            filename = file.filename or "image"
            path = f"vision/{domain}/{user_id}/{timestamp}/{filename}"

            logger.info(f"Mock upload: {path}")
            return path

            # Real implementation:
            # contents = await file.read()
            # path = f"vision/{domain}/{user_id}/{datetime.utcnow().isoformat()}/{file.filename}"
            # response = self.supabase.storage.from_(self.bucket_name).upload(path, contents)
            # if response:
            #     return self.supabase.storage.from_(self.bucket_name).get_public_url(path)
            # else:
            #     raise Exception("Upload failed")

        except Exception as e:
            logger.error(f"Error uploading image: {e}")
            raise

    async def upload_images(
        self,
        files: List[UploadFile],
        user_id: str,
        domain: str,
    ) -> List[str]:
        """Upload multiple images"""
        paths = []
        for file in files:
            path = await self.upload_image(file, user_id, domain)
            paths.append(path)
        return paths

    def get_image_url(self, path: str) -> str:
        """Get public URL for an image path"""
        # TODO: Implement when Supabase storage is set up
        return f"{self.supabase_url}/storage/v1/object/public/{self.bucket_name}/{path}"

    async def delete_image(self, path: str) -> bool:
        """Delete image from storage"""
        try:
            # TODO: Implement real deletion
            logger.info(f"Mock delete: {path}")
            return True
        except Exception as e:
            logger.error(f"Error deleting image: {e}")
            return False
