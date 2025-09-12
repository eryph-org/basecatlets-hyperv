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

import json
import time
import uuid
try:
    import winreg
except ImportError:
    winreg = None

from oslo_log import log as oslo_logging

from cloudbaseinit import conf as cloudbaseinit_conf
from cloudbaseinit import exception

CONF = cloudbaseinit_conf.CONF
LOG = oslo_logging.getLogger(__name__)

# HyperV KVP Exchange registry path for guest-to-host communication
HYPERV_KVP_GUEST_KEY = r"SOFTWARE\Microsoft\Virtual Machine\Guest"


class HyperVKvpReporter(object):
    """HyperV Key-Value Pair reporter for provisioning status.
    
    This class implements a reporter that writes provisioning status
    to the Windows registry using HyperV's KVP exchange mechanism.
    The format follows cloud-init's HyperV KVP reporter format for
    compatibility.
    """

    def __init__(self):
        try:
            self._incarnation = CONF.hyperv_kvp_incarnation or "0"
        except Exception:
            LOG.warning("Could not access hyperv_kvp_incarnation config, using default")
            self._incarnation = "0"
        self._instance_uuid = str(uuid.uuid4())

    def _get_kvp_key_name(self, event_type, event_name):
        """Generate KVP key name following cloud-init format."""
        event_uuid = str(uuid.uuid4())
        return "CLOUDBASE_INIT|{}|{}|{}|{}".format(
            self._incarnation, event_type, event_name, event_uuid)

    def _write_to_registry(self, key_name, value):
        """Write KVP data to Windows registry."""
        if not winreg:
            LOG.warning("winreg module not available, cannot write KVP data")
            return False

        try:
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,
                              HYPERV_KVP_GUEST_KEY,
                              0, winreg.KEY_WRITE) as reg_key:
                winreg.SetValueEx(reg_key, key_name, 0, winreg.REG_SZ, value)
                LOG.debug("Written KVP data: %s = %s", key_name, value)
                return True
        except OSError as ex:
            LOG.warning("Failed to write KVP data to registry: %s", ex)
            return False

    def _create_event_data(self, event_type, event_name, result="SUCCESS", 
                          description=None):
        """Create event data structure compatible with cloud-init format."""
        event_data = {
            "name": event_name,
            "timestamp": time.time(),
            "result": result,
            "event_type": event_type,
            "origin": "cloudbase-init",
            "instance_id": self._instance_uuid,
        }
        
        if description:
            event_data["description"] = description
            
        return json.dumps(event_data, separators=(',', ':'))

    def report_event(self, event_type, event_name, result="SUCCESS", 
                    description=None):
        """Report an event via HyperV KVP exchange."""
        try:
            key_name = self._get_kvp_key_name(event_type, event_name)
            event_data = self._create_event_data(event_type, event_name, 
                                               result, description)
            
            success = self._write_to_registry(key_name, event_data)
            if success:
                LOG.info("Reported event via KVP: %s/%s (%s)", 
                        event_type, event_name, result)
            else:
                LOG.error("Failed to report event via KVP: %s/%s", 
                         event_type, event_name)
                
        except Exception as ex:
            LOG.error("Error reporting KVP event %s/%s: %s", 
                     event_type, event_name, ex)

    def report_provisioning_started(self):
        """Report that provisioning has started."""
        self.report_event("provisioning", "started", "SUCCESS",
                         "Cloudbase-Init provisioning started")

    def report_provisioning_completed(self):
        """Report that provisioning has completed successfully."""
        self.report_event("provisioning", "completed", "SUCCESS",
                         "Cloudbase-Init provisioning completed successfully")

    def report_provisioning_failed(self, error=None):
        """Report that provisioning has failed."""
        description = "Cloudbase-Init provisioning failed"
        if error:
            description = "{}: {}".format(description, error)
        
        self.report_event("provisioning", "failed", "FAILURE", description)

    def report_stage_event(self, stage_name, event_name, result="SUCCESS", 
                          description=None):
        """Report a stage-specific event."""
        self.report_event("stage", "{}/{}".format(stage_name, event_name),
                         result, description)