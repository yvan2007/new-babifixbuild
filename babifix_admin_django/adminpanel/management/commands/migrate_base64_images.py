"""
Management command to migrate base64 images to file storage.
Usage: python manage.py migrate_base64_images
"""

import base64
import os
from django.core.management.base import BaseCommand
from django.conf import settings
from adminpanel.models import Client, Provider


class Command(BaseCommand):
    help = "Migrate base64 image fields to file storage"

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Show what would be migrated without actually migrating",
        )

    def handle(self, *args, **options):
        dry_run = options.get("dry_run", False)

        self.stdout.write(self.style.WARNING("Starting base64 to file migration..."))

        # Create media directory if it doesn't exist
        media_root = settings.MEDIA_ROOT
        avatars_dir = os.path.join(media_root, "avatars")
        if not dry_run:
            os.makedirs(avatars_dir, exist_ok=True)

        # Migrate Client avatars
        clients = Client.objects.exclude(avatar__isnull=True).exclude(avatar="")
        self.stdout.write(f"Found {clients.count()} clients with avatars")

        for client in clients:
            if self._is_base64(client.avatar):
                if dry_run:
                    self.stdout.write(f"  [DRY RUN] Would migrate client {client.id}")
                else:
                    self._migrate_base64_field(client, "avatar", "client", avatars_dir)
                    self.stdout.write(f"  Migrated client {client.id}")

        # Migrate Provider photos
        providers = Provider.objects.exclude(photo__isnull=True).exclude(photo="")
        self.stdout.write(f"Found {providers.count()} providers with photos")

        for provider in providers:
            if self._is_base64(provider.photo):
                if dry_run:
                    self.stdout.write(
                        f"  [DRY RUN] Would migrate provider {provider.id}"
                    )
                else:
                    self._migrate_base64_field(
                        provider, "photo", "provider", avatars_dir
                    )
                    self.stdout.write(f"  Migrated provider {provider.id}")

        self.stdout.write(self.style.SUCCESS("Migration complete!"))

    def _is_base64(self, value):
        """Check if a string looks like base64 encoded data"""
        if not value or not isinstance(value, str):
            return False
        return value.startswith("data:") or len(value) > 200

    def _migrate_base64_field(self, instance, field_name, prefix, dest_dir):
        """Convert base64 string to file and update model"""
        value = getattr(instance, field_name)

        # Extract base64 data
        if "base64," in value:
            header, base64_data = value.split("base64,", 1)
            # Extract extension from header
            ext = ".jpg"
            if "image/png" in header:
                ext = ".png"
            elif "image/webp" in header:
                ext = ".webp"
        else:
            base64_data = value
            ext = ".jpg"

        # Decode and save
        try:
            image_data = base64.b64decode(base64_data)
            filename = f"{prefix}_{instance.id}_{field_name}{ext}"
            filepath = os.path.join(dest_dir, filename)

            with open(filepath, "wb") as f:
                f.write(image_data)

            # Update model with file path
            setattr(instance, field_name, f"avatars/{filename}")
            instance.save(update_fields=[field_name])
        except Exception as e:
            self.stdout.write(self.style.ERROR(f"Error migrating {field_name}: {e}"))
