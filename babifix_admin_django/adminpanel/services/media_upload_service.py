"""
Media Upload Service — Upload vers S3/Cloudinary
Remplace le stockage base64 par des URLs CDN
"""
import base64
import hashlib
import logging
import os
from dataclasses import dataclass
from typing import Optional

from django.conf import settings

logger = logging.getLogger(__name__)


@dataclass
class UploadResult:
    """Resultat d'un upload."""
    success: bool
    url: Optional[str] = None
    error: Optional[str] = None


def _generate_filename(content: bytes, prefix: str = "babifix") -> str:
    """Genere un nom de fichier unique."""
    import secrets
    hash = hashlib.md5(content).hexdigest()[:8]
    ext = _detect_extension(content)
    return f"{prefix}/{secrets.token_hex(8)}{ext}"


def _detect_extension(content: bytes) -> str:
    """Detecte l'extension baseada sur les bytes magic."""
    if content.startswith(b'\xff\xd8'):
        return ".jpg"
    elif content.startswith(b'\x89PNG'):
        return ".png"
    elif content.startswith(b'GIF'):
        return ".gif"
    elif content.startswith(b'RIFF') and b'WEBP' in content[:12]:
        return ".webp"
    return ".jpg"


class MediaUploadService:
    """Service d'upload d'images vers CDN.
    
    Configuration (settings.py):
        MEDIA_CDN_PROVIDER: 's3' ou 'cloudinary'
        AWS_S3_BUCKET: nom du bucket S3
        AWS_ACCESS_KEY_ID: cle access
        AWS_SECRET_ACCESS_KEY: cle secrete
        AWS_REGION: region AWS
        CLOUDINARY_CLOUD_NAME: nom cloudinary
        CLOUDINARY_API_KEY: cle API
        CLOUDINARY_API_SECRET: secrete API
    """
    
    @classmethod
    def upload_image(
        cls,
        base64_data: str,
        folder: str = "babifix",
    ) -> UploadResult:
        """
        Upload une image base64 vers le CDN.
        
        Args:
            base64_data: Chaine base64 (data:image/xxx;base64,XXX)
            folder: Dossier de destination
            
        Returns:
            UploadResult avec url ou erreur
        """
        try:
            # Decoder le base64
            if "," in base64_data:
                # Enlever le prefix data:image/xxx;base64,
                header, data = base64_data.split(",", 1)
            else:
                data = base64_data
            
            image_bytes = base64.b64decode(data)
            
            # Detecter le type
            ext = _detect_extension(image_bytes)
            filename = _generate_filename(image_bytes, folder)
            
            # Upload vers le provider configure
            provider = getattr(settings, "MEDIA_CDN_PROVIDER", "s3")
            
            if provider == "s3":
                return cls._upload_s3(image_bytes, filename)
            elif provider == "cloudinary":
                return cls._upload_cloudinary(image_bytes, filename)
            else:
                # Fallback local (dev only)
                return cls._upload_local(image_bytes, filename)
                
        except Exception as e:
            logger.exception(f"Upload failed: {e}")
            return UploadResult(success=False, error=str(e))
    
    @classmethod
    def _upload_s3(cls, content: bytes, key: str) -> UploadResult:
        """Upload vers AWS S3."""
        try:
            import boto3
            from botocore.exceptions import ClientError
            
            bucket = getattr(settings, "AWS_S3_BUCKET", None)
            if not bucket:
                return UploadResult(success=False, error="S3 bucket not configured")
            
            s3_client = boto3.client(
                's3',
                aws_access_key_id=getattr(settings, "AWS_ACCESS_KEY_ID", ""),
                aws_secret_access_key=getattr(settings, "AWS_SECRET_ACCESS_KEY", ""),
                region_name=getattr(settings, "AWS_REGION", "eu-west-1"),
            )
            
            # Detect content type
            content_type = "image/jpeg"
            if key.endswith(".png"):
                content_type = "image/png"
            elif key.endswith(".gif"):
                content_type = "image/gif"
            elif key.endswith(".webp"):
                content_type = "image/webp"
            
            s3_client.put_object(
                Bucket=bucket,
                Key=key,
                Body=content,
                ContentType=content_type,
                ACL='public-read',
            )
            
            url = f"https://{bucket}.s3.amazonaws.com/{key}"
            return UploadResult(success=True, url=url)
            
        except Exception as e:
            logger.error(f"S3 upload error: {e}")
            return UploadResult(success=False, error=f"S3 error: {e}")
    
    @classmethod
    def _upload_cloudinary(cls, content: bytes, public_id: str) -> UploadResult:
        """Upload vers Cloudinary."""
        try:
            import cloudinary
            import cloudinary.api
            import cloudinary.uploader
            
            cloudinary.config(
                cloud_name=getattr(settings, "CLOUDINARY_CLOUD_NAME", ""),
                api_key=getattr(settings, "CLOUDINARY_API_KEY", ""),
                api_secret=getattr(settings, "CLOUDINARY_API_SECRET", ""),
            )
            
            import io
            result = cloudinary.uploader.upload_file(
                io.BytesIO(content),
                public_id=public_id,
                resource_type="image",
            )
            
            return UploadResult(
                success=True,
                url=result.get("secure_url"),
            )
            
        except Exception as e:
            logger.error(f"Cloudinary upload error: {e}")
            return UploadResult(success=False, error=f"Cloudinary error: {e}")
    
    @classmethod
    def _upload_local(cls, content: bytes, key: str) -> UploadResult:
        """Upload local (dev only)."""
        import os
        from django.conf import settings
        
        media_root = getattr(settings, "MEDIA_ROOT", "media")
        os.makedirs(media_root, exist_ok=True)
        
        path = os.path.join(media_root, key)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        
        with open(path, "wb") as f:
            f.write(content)
        
        from django.conf import settings
        base_url = getattr(settings, "MEDIA_URL", "/media/")
        return UploadResult(
            success=True,
            url=f"{base_url}{key}",
        )
    
    @classmethod
    def upload_photo_attachments(
        cls,
        base64_list: list,
        folder: str = "photos",
        max_size_mb: float = 5.0,
    ) -> list[str]:
        """
        Upload plusieurs photos.
        
        Args:
            base64_list: Liste de strings base64
            folder: Dossier
            max_size_mb: Taille max par image
            
        Returns:
            Liste d'URLs ou liste vide
        """
        urls = []
        max_bytes = int(max_size_mb * 1024 * 1024)
        
        for b64 in base64_list[:6]:  # Max 6 photos
            # Check taille avant decoder (rough)
            if len(b64) > max_bytes * 4 // 3:
                logger.warning(f"Image trop grande ({len(b64)} bytes)")
                continue
            
            result = cls.upload_image(b64, folder)
            if result.success and result.url:
                urls.append(result.url)
        
        return urls