# Copyright 2026 dbosoft GmbH
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

"""Metadata service exposing Azure CustomData.bin to cloudbase-init.

When eryph's Windows images run on Azure, Microsoft's Provisioning Agent
(PA) consumes the Azure config-drive ISO during oobeSystem, applies
hostname / admin user / RDP from ovf-env.xml, then ejects the ISO.
cloudbase-init runs after PA (re-enabled via SetupComplete2.cmd) but has
no metadata source: NoCloud finds no ``cidata`` CD-ROM, and the stock
AzureService cannot ``load()`` because the PA tag file is gone.

This service reads the user data Azure left on disk at
``C:\\AzureData\\CustomData.bin`` and surfaces a stable instance-id from
``HKLM\\SOFTWARE\\Microsoft\\Windows Azure\\VmId`` (same GUID that Azure
IMDS publishes as ``compute.vmId``), so cloudbase-init's UserDataPlugin
runs the customData (typically a ``#include <url>`` directive produced
by the eryph deployagent) and its plugin-status tracking is stable
across reboots.
"""

import os

try:
    import winreg
except ImportError:
    winreg = None

from oslo_log import log as oslo_logging

from cloudbaseinit.metadata.services import base


LOG = oslo_logging.getLogger(__name__)

CUSTOM_DATA_PATH = r"C:\AzureData\CustomData.bin"

_AZURE_VMID_KEY = r"SOFTWARE\Microsoft\Windows Azure"
_AZURE_VMID_VALUE = "VmId"

_HYPERV_KVP_KEY = r"SOFTWARE\Microsoft\Virtual Machine\Guest\Parameters"
_HYPERV_VMID_VALUE = "VirtualMachineId"


class AzureCustomDataService(base.BaseMetadataService):
    """Surface Azure CustomData.bin as a cloudbase-init metadata source.

    Runs after Microsoft's Provisioning Agent. PA already handled
    hostname / admin user / RDP via ovf-env.xml during oobeSystem; this
    service only exposes user data and a stable instance-id.
    """

    def __init__(self):
        super(AzureCustomDataService, self).__init__()
        self._user_data = None
        self._instance_id = None

    def _get_data(self, path):
        pass

    def load(self):
        super(AzureCustomDataService, self).load()
        if not os.path.exists(CUSTOM_DATA_PATH):
            LOG.debug("Azure CustomData.bin not present at %s",
                      CUSTOM_DATA_PATH)
            return False
        try:
            with open(CUSTOM_DATA_PATH, "rb") as f:
                self._user_data = f.read()
        except (IOError, OSError) as ex:
            LOG.warning("Failed to read %s: %s", CUSTOM_DATA_PATH, ex)
            return False
        if not self._user_data:
            LOG.debug("Azure CustomData.bin is empty; nothing to apply")
            return False

        self._instance_id = self._read_instance_id()
        if not self._instance_id:
            # Without a stable id, cloudbase-init's plugin-status tracking
            # treats every boot as a new instance and re-runs everything.
            # Still better than refusing to run on a host that's missing
            # the registry value for some reason.
            LOG.warning(
                "Loaded Azure CustomData.bin but found no VmId in registry; "
                "falling back to a non-unique instance-id.")
            self._instance_id = "azure-customdata"

        LOG.info(
            "Azure CustomData service loaded (%d bytes, instance-id=%s)",
            len(self._user_data), self._instance_id)
        return True

    def _read_instance_id(self):
        if winreg is None:
            return None
        vmid = self._read_registry_value(
            winreg.HKEY_LOCAL_MACHINE,
            _AZURE_VMID_KEY, _AZURE_VMID_VALUE)
        if vmid:
            return "azure-%s" % vmid
        vmid = self._read_registry_value(
            winreg.HKEY_LOCAL_MACHINE,
            _HYPERV_KVP_KEY, _HYPERV_VMID_VALUE)
        if vmid:
            return "hyperv-%s" % vmid
        return None

    @staticmethod
    def _read_registry_value(hive, subkey, name):
        try:
            with winreg.OpenKey(hive, subkey, 0, winreg.KEY_READ) as key:
                value, _ = winreg.QueryValueEx(key, name)
                return value
        except OSError:
            return None

    def get_user_data(self):
        return self._user_data

    def get_instance_id(self):
        return self._instance_id

    def get_host_name(self):
        # PA already applied ComputerName from ovf-env.xml. Returning None
        # makes SetHostNamePlugin no-op cleanly.
        return None

    # get_admin_username / get_admin_password are intentionally NOT
    # overridden. CreateUserPlugin / SetUserPasswordPlugin call them
    # directly and propagate any exception; the base class returning
    # None is the only graceful path. Same behavior as the NoCloud
    # service when its metadata omits admin fields.

    def provisioning_completed(self):
        # Fires only when every plugin finished and no plugin requested
        # a reboot (init.py:228-232) — i.e. cloudbase-init is truly done
        # with this instance_id. Drop CustomData.bin so a future re-run
        # of this service won't re-process the (now-applied) payload,
        # and remove C:\AzureData if it's empty afterwards. Plugin status
        # is keyed off VmId in the registry, so a real Azure redeploy
        # (which rotates VmId) still gets a fresh apply via a freshly
        # written CustomData.bin from the new ovf-env.
        super(AzureCustomDataService, self).provisioning_completed()
        try:
            if os.path.exists(CUSTOM_DATA_PATH):
                os.unlink(CUSTOM_DATA_PATH)
                LOG.info("Removed %s after successful provisioning",
                         CUSTOM_DATA_PATH)
        except OSError as ex:
            LOG.warning("Failed to remove %s: %s", CUSTOM_DATA_PATH, ex)
            return
        parent = os.path.dirname(CUSTOM_DATA_PATH)
        try:
            os.rmdir(parent)
            LOG.info("Removed empty directory %s", parent)
        except OSError:
            # Non-empty (other Azure artifacts) or already gone — leave alone.
            pass
