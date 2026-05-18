# Copyright 2024 Cloudbase Solutions Srl
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

import io
import gzip
import requests
import email
from oslo_log import log as oslo_logging
from urllib.parse import urlparse

from cloudbaseinit import conf as cloudbaseinit_conf
from cloudbaseinit.plugins.common.userdataplugins import base
from cloudbaseinit.plugins.common import execcmd
from cloudbaseinit.utils import encoding

CONF = cloudbaseinit_conf.CONF
LOG = oslo_logging.getLogger(__name__)


class IncludeUrlPlugin(base.BaseUserDataPlugin):

    def __init__(self):
        super(IncludeUrlPlugin, self).__init__("text/x-include-url")

    def process(self, part):
        """Process include URL part by fetching URLs and processing their content.

        :param part: The part containing URLs to include, one per line
        :returns: Plugin execution status
        """
        LOG.debug("Processing include URL part")

        try:
            payload = part.get_payload(decode=True)
            if isinstance(payload, bytes):
                payload = payload.decode('utf-8')

            urls = self._parse_urls(payload)

            for url in urls:
                if not url.strip():
                    continue

                LOG.debug("Processing include URL: %s", url)

                try:
                    content = self._fetch_url_content(url)
                    if content:
                        ret_val = self._process_included_content(content)
                        if ret_val and ret_val != 0:
                            LOG.warning("Include URL content processing returned: %s", ret_val)
                except Exception as ex:
                    LOG.error("Failed to process include URL '%s': %s", url, ex)
                    # Stop processing remaining URLs on error (cloud-init behavior)
                    break

        except Exception as ex:
            LOG.error("Failed to process include URL part: %s", ex)
            return (1, False)

        return (0, False)

    def _parse_urls(self, content):
        """Parse URLs from the content, one per line.

        :param content: String content with URLs
        :returns: List of URLs
        """
        urls = []
        for line in content.splitlines():
            line = line.strip()
            if line and not line.startswith('#'):
                urls.append(line)
        return urls

    def _fetch_url_content(self, url):
        """Fetch content from URL with error handling and decompression.

        :param url: URL to fetch
        :returns: Content as bytes or None if failed
        """
        try:
            # Validate URL
            parsed = urlparse(url)
            if not parsed.scheme or not parsed.netloc:
                LOG.error("Invalid URL format: %s", url)
                return None

            if parsed.scheme not in ('http', 'https'):
                LOG.error("Unsupported URL scheme: %s", parsed.scheme)
                return None

            # Fetch content with timeout
            response = requests.get(url, timeout=30, stream=True)
            response.raise_for_status()

            content = response.content

            # Handle gzip compression
            if self._is_gzipped(content):
                LOG.debug("Decompressing gzipped content from URL: %s", url)
                content = gzip.decompress(content)

            LOG.debug("Successfully fetched %d bytes from URL: %s", len(content), url)
            return content

        except requests.exceptions.RequestException as ex:
            LOG.error("HTTP request failed for URL '%s': %s", url, ex)
            return None
        except Exception as ex:
            LOG.error("Failed to fetch URL '%s': %s", url, ex)
            return None

    def _is_gzipped(self, content):
        """Check if content is gzip compressed.

        :param content: Content to check
        :returns: True if gzipped
        """
        return content.startswith(b'\x1f\x8b')

    def _process_included_content(self, content):
        """Process included content through user data processing pipeline.

        :param content: Content to process as bytes
        :returns: Processing result
        """
        # Import here to avoid circular imports
        from cloudbaseinit.plugins.common import userdatautils
        from cloudbaseinit.plugins.common.userdataplugins import factory

        if not content:
            LOG.warning("Empty content received for processing")
            return 1

        LOG.debug("Processing included content of %d bytes", len(content))

        try:
            # Check if it's multipart content
            if self._is_multipart_content(content):
                LOG.debug("Processing included content as multipart MIME")
                return self._process_multipart_content(content)

            # Detect content type and process accordingly
            if content.startswith(b'#cloud-config'):
                LOG.debug("Processing included content as cloud-config")
                user_data_plugins = factory.load_plugins()
                cloud_config_plugin = user_data_plugins.get('text/cloud-config')
                if cloud_config_plugin:
                    ret_val = cloud_config_plugin.process_non_multipart(content)
                    # Extract return code from tuple if needed
                    if isinstance(ret_val, tuple):
                        ret_val = ret_val[0]
                else:
                    LOG.warning("Cloud-config plugin not available")
                    ret_val = 1
            elif content.startswith(b'#include'):
                LOG.debug("Processing included content as nested include URL")
                # Handle nested includes by processing recursively
                user_data_plugins = factory.load_plugins()
                include_url_plugin = user_data_plugins.get('text/x-include-url')
                if include_url_plugin:
                    # Create a mock part object for the include plugin
                    from collections import namedtuple
                    MockPart = namedtuple('MockPart', ['get_payload', 'get_filename'])
                    mock_part = MockPart(
                        get_payload=lambda decode=False: content if not decode else content,
                        get_filename=lambda: 'nested-include-urls'
                    )
                    ret_val = include_url_plugin.process(mock_part)
                    # Extract return code from tuple if needed
                    if isinstance(ret_val, tuple):
                        ret_val = ret_val[0]
                else:
                    LOG.warning("Include URL plugin not available for nested processing")
                    ret_val = 1
            else:
                # Process as regular user data script
                LOG.debug("Processing included content as user data script")
                ret_val = userdatautils.execute_user_data_script(content)

            return ret_val

        except Exception as ex:
            LOG.error("Failed to process included content: %s", ex)
            return 1

    def _is_multipart_content(self, content):
        """Check if content is multipart MIME.

        :param content: Content to check as bytes
        :returns: True if multipart
        """
        try:
            content_str = encoding.get_as_string(content)
            # Check for multipart content type (any multipart subtype)
            return ('Content-Type: multipart/' in content_str or
                    content_str.lstrip().startswith('Content-Type: multipart/'))
        except Exception:
            return False

    def _process_multipart_content(self, content):
        """Process multipart MIME content.

        :param content: Multipart content as bytes
        :returns: Processing result
        """
        try:
            # Import here to avoid circular imports
            from cloudbaseinit.plugins.common.userdataplugins import factory

            content_str = encoding.get_as_string(content)
            user_data_plugins = factory.load_plugins()
            user_handlers = {}

            LOG.debug("Processing multipart included content")

            for part in email.message_from_string(content_str).walk():
                content_type = part.get_content_type()

                # Skip the multipart container itself
                if content_type.startswith('multipart/'):
                    continue

                LOG.debug("Processing multipart part with content type: %s", content_type)

                user_data_plugin = user_data_plugins.get(content_type)
                if user_data_plugin:
                    LOG.debug("Executing userdata plugin: %s", user_data_plugin.__class__.__name__)
                    ret_val = user_data_plugin.process(part)

                    # Extract return code from tuple if needed
                    if isinstance(ret_val, tuple):
                        ret_val = ret_val[0]

                    if ret_val and ret_val != 0:
                        LOG.warning("Multipart processing returned: %s", ret_val)
                        return ret_val
                else:
                    LOG.info("Userdata plugin not found for content type: %s", content_type)

            return 0

        except Exception as ex:
            LOG.error("Failed to process multipart included content: %s", ex)
            return 1