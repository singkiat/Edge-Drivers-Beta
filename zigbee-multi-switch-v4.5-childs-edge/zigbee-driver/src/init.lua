-- Copyright 2021 SmartThings
--- M. Colmenarejo 2022
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local button = require "st.capabilities".button
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
--local device_management = require "st.zigbee.device_management"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local OnOff = zcl_clusters.OnOff
local data_types = require "st.zigbee.data_types"
--local cluster_base = require "st.zigbee.cluster_base"
local utils = require "st.utils"
local ElectricalMeasurement = zcl_clusters.ElectricalMeasurement
local SimpleMetering = zcl_clusters.SimpleMetering
local zcl_global_commands = require "st.zigbee.zcl.global_commands"

local write_attribute = require "st.zigbee.zcl.global_commands.write_attribute"
local read_attribute = require "st.zigbee.zcl.global_commands.read_attribute"
local zcl_messages = require "st.zigbee.zcl"
local messages = require "st.zigbee.messages"
local zb_const = require "st.zigbee.constants"
--local Groups = zcl_clusters.Groups
local Status = require "st.zigbee.generated.types.ZclStatus"
local ep_ini = 1

local child_devices = require "child-devices"
local signal = require "signal-metrics"
local write = require "writeAttribute"

-- Custom Capabilities Declaration
local switch_All_On_Off = capabilities["legendabsolute60149.switchAllOnOff1"]
local signal_Metrics = capabilities["legendabsolute60149.signalMetrics"]

  --tuyaBlackMagic() {return zigbee.readAttribute(0x0000, [0x0004, 0x000, 0x0001, 0x0005, 0x0007, 0xfffe], [:], delay=200)}
  local function read_attribute_function(device, cluster_id, attr_id)
    if device.preferences.logDebugPrint == true then
      print("<<<< attr_id >>>>",utils.stringify_table(attr_id))
    end
    --local read_body = read_attribute.ReadAttribute({ attr_id }) --- Original lua librares
    local read_body = read_attribute.ReadAttribute( attr_id )
    local zclh = zcl_messages.ZclHeader({
      cmd = data_types.ZCLCommandId(read_attribute.ReadAttribute.ID)
    })

    local addrh = messages.AddressHeader(
        zb_const.HUB.ADDR,
        zb_const.HUB.ENDPOINT,
        device:get_short_address(),
        device:get_endpoint(cluster_id.value),
        zb_const.HA_PROFILE_ID,
        cluster_id.value
    )
    local message_body = zcl_messages.ZclMessageBody({
      zcl_header = zclh,
      zcl_body = read_body
    })
    return messages.ZigbeeMessageTx({
      address_header = addrh,
      body = message_body
    --}))
  })
  end

---- Check if device is using lumi combined profile ----
local function is_lumi_combined_profile(device)
  if device.preferences.logDebugPrint == true then
    print("DEBUG: Profile check - device.preferences.profile:", device.preferences.profile or "nil")
    print("DEBUG: Profile check - device.profile:", device.profile and device.profile.name or "nil")
    print("DEBUG: Looking for profile: lumi_three_switch_button_combined")
  end
  
  return device.preferences.profile == "lumi_three_switch_button_combined"
end

---- Update component capabilities based on individual switch coupling state ----
local function update_component_capabilities(device)
  if not is_lumi_combined_profile(device) then
    return
  end
  
  if device.preferences.logDebugPrint == true then
    print("Updating component capabilities based on decoupling state")
  end
  
  -- Use the clean pattern from web search - check capability support first
  if device:supports_capability_by_id(button.ID) then
    if device.preferences.logDebugPrint == true then
      print("DEBUG: Device supports button capability, setting up button attributes")
    end
    
    -- Set numberOfButtons (total buttons on device)
    local button_count = 3
    device:emit_event(button.numberOfButtons({ value = button_count }))
    if device.preferences.logDebugPrint == true then
      print("DEBUG: Set numberOfButtons:", button_count)
    end
    
    -- Set supportedButtonValues (what actions each button supports)
    local supported_values = {"pushed", "double"}  -- Only single and double press (event codes 1, 2)
    device:emit_event(button.supportedButtonValues({ value = supported_values }))
    if device.preferences.logDebugPrint == true then
      print("DEBUG: Set supportedButtonValues:", table.concat(supported_values, ", "))
    end
  else
    if device.preferences.logDebugPrint == true then
      print("WARNING: Device does not support button capability")
    end
  end
  
  -- Log current coupling states for debugging
  if device.preferences.logDebugPrint == true then
    print("Switch 1 coupling state:", device.preferences.decoupleSwitch1)
    print("Switch 2 coupling state:", device.preferences.decoupleSwitch2) 
    print("Switch 3 coupling state:", device.preferences.decoupleSwitch3)
  end
end

--- Update preferences after infoChanged recived ---
local function do_preferences (driver, device)
  if device.network_type == "DEVICE_EDGE_CHILD" then return end ---- device (is Child device)
  for id, value in pairs(device.preferences) do
    if device.preferences.logDebugPrint == true then
      print("device.preferences[infoChanged]=", device.preferences[id])
    end
    local oldPreferenceValue = device:get_field(id)
    local newParameterValue = device.preferences[id]
    if oldPreferenceValue ~= newParameterValue then
      device:set_field(id, newParameterValue, {persist = true})
      if device.preferences.logDebugPrint == true then
        print("<< Preference changed name:",id,"oldPreferenceValue:",oldPreferenceValue, "newParameterValue: >>", newParameterValue)
      end
      ------ Change profile & Icon
      if id == "changeProfileThreePlug" then
       if newParameterValue == "Single" then
        device:try_update_metadata({profile = "three-outlet"})
       else
        device:try_update_metadata({profile = "three-outlet-multi"})
       end
      elseif id == "changeProfileThreeSw" then
        if newParameterValue == "Single" then
         device:try_update_metadata({profile = "three-switch"})
        else
         device:try_update_metadata({profile = "three-switch-multi"})
        end
      elseif id == "changeProfileTwoPlug" then
        if newParameterValue == "Single" then
          device:try_update_metadata({profile = "two-outlet"})
        else
          device:try_update_metadata({profile = "two-outlet-multi"})
        end
      elseif id == "changeProfileTwoPlugPw" then
        if newParameterValue == "Single" then
          device:try_update_metadata({profile = "two-plug-power"})
        else
          device:try_update_metadata({profile = "two-plug-power-multi"})
        end
      elseif id == "changeProfileTwoSwPw" then
        if newParameterValue == "Single" then
          device:try_update_metadata({profile = "two-switch-power-energy"})
        else
          device:try_update_metadata({profile = "two-switch-power-energy-multi"})
        end
      elseif id == "changeProfileTwoSwPw1" then
        if newParameterValue == "Single" then
          device:try_update_metadata({profile = "two-switch-power-energy-1"})
        else
          device:try_update_metadata({profile = "two-switch-power-energy-multi-1"})
        end
      elseif id == "changeProfileTwoSw" then
        if newParameterValue == "Single" then
         device:try_update_metadata({profile = "two-switch"})
        else
         device:try_update_metadata({profile = "two-switch-multi"})
        end
      elseif id == "changeProfileFourSw" then
        if newParameterValue == "Single" then
         device:try_update_metadata({profile = "four-switch"})
        else
         device:try_update_metadata({profile = "four-switch-multi"})
        end
      elseif id == "changeProfileFourPlug" then
        if newParameterValue == "Single" then
          device:try_update_metadata({profile = "four-outlet"})
        else
          device:try_update_metadata({profile = "four-outlet-multi"})
        end
      elseif id == "changeProfileFiveSw" then
        if device.preferences[id] == "Single" then
         device:try_update_metadata({profile = "five-switch"})
        else
         device:try_update_metadata({profile = "five-switch-multi"})
        end      
      elseif id == "changeProfileFivePlug" then
        if newParameterValue == "Single" then
          device:try_update_metadata({profile = "five-outlet"})
        else
          device:try_update_metadata({profile = "five-outlet-multi"})
        end
      elseif id == "changeProfileSix" then
        if newParameterValue == "Switch" then
          device:try_update_metadata({profile = "six-switch"})
        else
          device:try_update_metadata({profile = "five-outlet"})
        end
      elseif id == "changeProfileLumi" then
        if newParameterValue == "Multi" then
          device:try_update_metadata({profile = "lumi-two-switch-power-energy-1-multi"})
        else
          device:try_update_metadata({profile = "lumi-two-switch-power-energy-1"})
        end
      elseif id == "onOffReports" then
        if device:get_manufacturer() ~= "_TZ3000_fvh3pjaz" 
        and device:get_manufacturer() ~= "_TZ3000_wyhuocal" then -- devices turn off after 2 minutes
          -- Configure OnOff interval report
          local interval =  device.preferences.onOffReports
          if  device.preferences.onOffReports == nil then interval = 300 end
          local config ={
            cluster = zcl_clusters.OnOff.ID,
            attribute = zcl_clusters.OnOff.attributes.OnOff.ID,
            minimum_interval = 0,
            maximum_interval = interval,
            data_type = zcl_clusters.OnOff.attributes.OnOff.base_type
          }
          --device:send(zcl_clusters.OnOff.attributes.OnOff:configure_reporting(device, 0, interval))
          device:add_configured_attribute(config)
          device:add_monitored_attribute(config)
          device:configure()
        end
      end

      --- Configure on-off cluster, attributte 0x8002 and 4003 to value restore state in preferences
      if id == "restoreState" then
        for ids, value in pairs(device.profile.components) do
          if device.preferences.logDebugPrint == true then
            print("<<< Write restore state >>>")
          end
          local comp = device.profile.components[ids].id
          if comp == "main" then
            local endpoint = device:get_endpoint_for_component_id(comp)
            if device.preferences.logDebugPrint == true then
              print("<<<< Componente, end_point >>>>",comp, endpoint)
            end
            local value_send = tonumber(newParameterValue)
            local data_value = {value = value_send, ID = 0x30}
            local cluster_id = {value = 0x0006}
            --write atribute for standard devices
            local attr_id = 0x4003
            write.write_attribute_function(device, cluster_id, attr_id, data_value, endpoint)

            --write atribute for Tuya devices (Restore previous state = 0x02)
            if newParameterValue == "255" then data_value = {value = 0x02, ID = 0x30} end
            attr_id = 0x8002
            write.write_attribute_function(device, cluster_id, attr_id, data_value, endpoint)
          end
        end
      elseif id == "restoreStateLumi" then
        local value_send = tonumber(newParameterValue)
        local data_type = data_types.Uint8
        local cluster_id = 0xFCC0
        local attr_id = 0x0517
        local mfg_code = 0x115F
        device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value_send, mfg_code):to_endpoint (1))
        device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value_send, mfg_code):to_endpoint (2))
      elseif id == "interlockMode" then
        local value_send = tonumber(newParameterValue)
        value = false
        if value_send == 1 then value = true end
        local data_type = data_types.Boolean
        local cluster_id = 0xFCC0
        local attr_id = 0x02D0
        local mfg_code = 0x115F
        device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value, mfg_code):to_endpoint (1))
        device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value, mfg_code):to_endpoint (2))
      elseif id == "mode" then
        local value_send = tonumber(newParameterValue)
        local data_type = data_types.Uint8
        local cluster_id = 0xFCC0
        local attr_id = 0x0289
        local mfg_code = 0x115F
        device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value_send, mfg_code):to_endpoint (1))
        device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value_send, mfg_code):to_endpoint (2))
      elseif id == "dryPulseTime" then
        local value_send = newParameterValue
        local data_type = data_types.Uint16
        local cluster_id = 0xFCC0
        local attr_id = 0x00EB
        local mfg_code = 0x115F
        device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value_send, mfg_code):to_endpoint (1))
        device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value_send, mfg_code):to_endpoint (2))
      -- Decoupling preferences for lumi.switch.acn040 (verified IDs)
      elseif id == "decoupleSwitch1" then
        local value_send = tonumber(newParameterValue)  -- 0=decoupled, 1=coupled (control_relay)
        local data_type = data_types.Uint8
        local cluster_id = 0xFCC0
        local attr_id = 0x0200  -- Operation mode attribute (exactly as zigbee-herdsman-converters)
        local mfg_code = 0x115F
        device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value_send, mfg_code):to_endpoint (1))
        
        -- Update component capabilities after decoupling change
        update_component_capabilities(device)
      elseif id == "decoupleSwitch2" then
        local value_send = tonumber(newParameterValue)  -- 0=decoupled, 1=coupled (control_relay)
        local data_type = data_types.Uint8
        local cluster_id = 0xFCC0
        local attr_id = 0x0200  -- Operation mode attribute (exactly as zigbee-herdsman-converters)
        local mfg_code = 0x115F
        device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value_send, mfg_code):to_endpoint (2))
        
        -- Update component capabilities after decoupling change
        update_component_capabilities(device)
      elseif id == "decoupleSwitch3" then
        local value_send = tonumber(newParameterValue)  -- 0=decoupled, 1=coupled (control_relay)
        local data_type = data_types.Uint8
        local cluster_id = 0xFCC0
        local attr_id = 0x0200  -- Operation mode attribute (exactly as zigbee-herdsman-converters)
        local mfg_code = 0x115F
        device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value_send, mfg_code):to_endpoint (3))
        
        -- Update component capabilities after decoupling change
        update_component_capabilities(device)
      end
      -- Call to Create child device
      local profile_type = "child-switch"
      if id == "switch1Child" then
        if oldPreferenceValue ~= nil and newParameterValue == "Yes" then
         child_devices.create_new_device(driver, device, "main", profile_type)
        end       
      elseif id == "switch2Child" then
        if oldPreferenceValue ~= nil and newParameterValue == "Yes" then
         child_devices.create_new_device(driver, device, "switch2", profile_type)
        end
      elseif id == "switch2LevelChild" then
        if oldPreferenceValue ~= nil and newParameterValue == "Yes" then
          profile_type = "child-switch-level"
          child_devices.create_new_device(driver, device, "switch2", profile_type)
        end
      elseif id == "switch3Child" then
        if oldPreferenceValue ~= nil and newParameterValue == "Yes" then
          child_devices.create_new_device(driver, device, "switch3", profile_type)
        end
      elseif id == "switch3LevelChild" then
        if oldPreferenceValue ~= nil and newParameterValue == "Yes" then
          profile_type = "child-switch-level"
          child_devices.create_new_device(driver, device, "switch3", profile_type)
        end
      elseif id == "switch4Child" then
        if oldPreferenceValue ~= nil and newParameterValue == "Yes" then
          child_devices.create_new_device(driver, device, "switch4", profile_type)
        end
      elseif id == "switch5Child" then
        if oldPreferenceValue ~= nil and newParameterValue == "Yes" then
          child_devices.create_new_device(driver, device, "switch5",profile_type)
        end
      elseif id == "switch6Child" then
        if oldPreferenceValue ~= nil and newParameterValue == "Yes" then
          child_devices.create_new_device(driver, device, "switch6", profile_type)
        end
      end
    end
  end
  ---print manufacturer, model and leng of the strings
  if device.manufacturer == nil then    ---- device.manufacturer == nil is NO Child device
    local manufacturer = device:get_manufacturer()
    local model = device:get_model()
    local manufacturer_len = string.len(manufacturer)
    local model_len = string.len(model)

    print("Device ID", device)
    print("Manufacturer >>>", manufacturer, "Manufacturer_Len >>>",manufacturer_len)
    print("Model >>>", model,"Model_len >>>",model_len)
    -- This will print in the log the total memory in use by Lua in Kbytes
    print("Memory >>>>>>>",collectgarbage("count"), " Kbytes")

    local firmware_full_version = device.data.firmwareFullVersion
    if firmware_full_version == nil then firmware_full_version = "Unknown" end
    print("<<<<< Firmware Version >>>>>",firmware_full_version)
  end
end

-- Emit event for all Switch On-Off and child device
local function emit_event_all_On_Off(driver, device, total_on, total,status_Text)
  local child_device = device:get_child_by_parent_assigned_key("main")
  if total_on == total then
    device:emit_event(switch_All_On_Off.switchAllOnOff("All On"))
    if child_device ~= nil then
      child_device:emit_event(capabilities.switch.switch.on())
    end
  elseif total_on == 0 then
    device:emit_event(switch_All_On_Off.switchAllOnOff("All Off"))
    if child_device ~= nil then
      child_device:emit_event(capabilities.switch.switch.off())
    end
  elseif total_on > 0 and total_on < total then
    device:emit_event(switch_All_On_Off.switchAllOnOff(status_Text))
    if child_device ~= nil then
      child_device:emit_event(capabilities.switch.switch.off())
    end
  end
end

--- set All switch status
local function all_switches_status(driver,device)

  if device.preferences.logDebugPrint == true then
    print("all_switches_status >>>>>")
  end
   for id, value in pairs(device.preferences) do
     local total_on = 0
     local  total = 2
     local status_Text = ""
     if id == "changeProfileSix" then
      total = 6
      if device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S1:On "
      end
      if device:get_latest_state("switch2", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S2:On "
      end
      if device:get_latest_state("switch3", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S3:On "
      end
      if device:get_latest_state("switch4", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S4:On "
      end
      if device:get_latest_state("switch5", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S5:On "
      end
      if device:get_latest_state("switch6", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S6:On "
      end
      --print("Total_on >>>>>>", total_on,"Total >>>",total)

      emit_event_all_On_Off(driver, device, total_on, total,status_Text)

     elseif id == "changeProfileFivePlug" or id == "changeProfileFiveSw" then
      total = 5
      if device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S1:On "
      end
      if device:get_latest_state("switch2", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S2:On "
      end
      if device:get_latest_state("switch3", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S3:On "
      end
      if device:get_latest_state("switch4", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S4:On "
      end
      if device:get_latest_state("switch5", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S5:On "
      end
      --print("Total_on >>>>>>", total_on,"Total >>>",total)

      emit_event_all_On_Off(driver, device, total_on, total,status_Text)

    elseif id == "changeProfileFourPlug" or id == "changeProfileFourSw" then
       total = 4
       if device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
         total_on = total_on + 1
         status_Text = status_Text.."S1:On "
       end
       if device:get_latest_state("switch2", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
         total_on = total_on + 1
         status_Text = status_Text.."S2:On "
       end
       if device:get_latest_state("switch3", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
         total_on = total_on + 1
         status_Text = status_Text.."S3:On "
       end
       if device:get_latest_state("switch4", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
         total_on = total_on + 1
         status_Text = status_Text.."S4:On "
       end
       --print("Total_on >>>>>>", total_on,"Total >>>",total)
       emit_event_all_On_Off(driver, device, total_on, total,status_Text)
 
    -- elseif id == "changeProfileThreePlug" or id == "changeProfileThreeSw" then
    elseif (id == "switch3Child" and device.preferences.switch4Child == nil) then
     total = 3
     if device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
       total_on = total_on + 1
       status_Text = status_Text.."S1:On "
     end
     if device:get_latest_state("switch2", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
       total_on = total_on + 1
       status_Text = status_Text.."S2:On "
     end
     if device:get_latest_state("switch3", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
       total_on = total_on + 1
       status_Text = status_Text.."S3:On "
     end
     --print("Total_on >>>>>>", total_on,"Total >>>",total)
     emit_event_all_On_Off(driver, device, total_on, total,status_Text)
 
    elseif id == "changeProfileTwoPlug" or 
    id == "changeProfileTwoSw" or 
    id == "changeProfileTwoSwPw1" or
    id == "changeProfileTwoPlugPw" or
    (id == "switch2LevelChild" and device.preferences.switch3Child == nil) or
    (id == "switch2Child" and device.preferences.switch3Child == nil) then
     if device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
       total_on = total_on + 1
       status_Text = status_Text.."S1:On "
     end
     if device:get_latest_state("switch2", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
       total_on = total_on + 1
       status_Text = status_Text.."S2:On "
     end
     --print("Total_on >>>>>>", total_on,"Total >>>",total)
     emit_event_all_On_Off(driver, device, total_on, total,status_Text)
 
    end
   end

 end

 --- return endpoint from component_id
local function component_to_endpoint(device, component_id)
  if device.preferences.logDebugPrint == true then
    print("<<<<< device.fingerprinted_endpoint_id >>>>>>",device.fingerprinted_endpoint_id)
  end
  --------- in this models device.fingerprinted_endpoint_id is the last endpoint
  local endpoint_odd = false
  if device:get_model() == "FB56+ZSW1JKJ2.7" or 
    device:get_model()=="FB56+ZSW1IKJ2.5" or 
    device:get_model()=="FB56+ZSW1HKJ2.5" or
    device:get_model()=="FB56+ZSW1IKJ1.7" or
    device:get_model()=="FB56+ZSW1JKJ2.5" or
    device:get_model()=="FB56+ZSW1HKJ2.7"  then
      ep_ini = 16
  elseif device:get_model() == "LM-SZ2" or device:get_model() == "LM-SZ3" or device:get_model() == "LM-SZ4" then
    ep_ini = 1
    endpoint_odd = true -- use odd endpoints only LUMI and Lumi Vietnam
  elseif device:get_model() == "lumi.switch.acn040" then
    -- Special mapping for lumi.acn040 (corrected: endpoints 1,2,3)
    if component_id == "main" then
      return 1
    elseif component_id == "switch2" then
      return 2
    elseif component_id == "switch3" then
      return 3
    end
  else
    ep_ini = device.fingerprinted_endpoint_id
  end

  if component_id == "main" then
    return ep_ini
  else
    local ep_num = component_id:match("switch(%d)")
    if ep_num == "2" then
      if endpoint_odd == true then
        return 3
      else
        return ep_ini + 1
      end
    elseif ep_num == "3" then
      if endpoint_odd == true then
        return 5
      else
        return ep_ini + 2
      end
    elseif ep_num == "4" then
      if endpoint_odd == true then
        return 7
      else
        return ep_ini + 3
      end
    elseif ep_num == "5" then
      if device:get_manufacturer() == "_TYZB01_vkwryfdr" then
        return ep_ini + 6
      else
        return ep_ini + 4
      end
    elseif ep_num == "6" then
      return ep_ini + 5
    end
  end
end

--- return Component_id from endpoint
local function endpoint_to_component(device, ep)

  if device.preferences.logDebugPrint == true then
    print("<<<<< device.fingerprinted_endpoint_id >>>>>>",device.fingerprinted_endpoint_id)
  end
  ------------------ in this models device.fingerprinted_endpoint_id is the last endpoint
  local endpoint_odd = false
  if device:get_model() == "FB56+ZSW1JKJ2.7" or 
    device:get_model()=="FB56+ZSW1IKJ2.5" or 
    device:get_model()=="FB56+ZSW1HKJ2.5" or
    device:get_model()=="FB56+ZSW1IKJ1.7" or
    device:get_model()=="FB56+ZSW1JKJ2.5" or
    device:get_model()=="FB56+ZSW1HKJ2.7" then
      ep_ini = 16
  elseif device:get_model() == "LM-SZ2" or device:get_model() == "LM-SZ3" or device:get_model() == "LM-SZ4" then
      ep_ini = 1
      endpoint_odd = true -- use odd endpoints only LUMI and Lumi Vietnam
  elseif device:get_model() == "lumi.switch.acn040" then
    -- Special mapping for lumi.acn040 (corrected: endpoints 1,2,3)
    if ep == 1 then
      return "main"
    elseif ep == 2 then
      return "switch2"
    elseif ep == 3 then
      return "switch3"
    end
    return nil -- Unknown endpoint for this device
  else
    ep_ini = device.fingerprinted_endpoint_id
  end

  if ep == ep_ini then
    return "main"
  else
    if ep == ep_ini + 1 and endpoint_odd == false then
      --return string.format("switch%d", ep)
      return "switch2"
    elseif ep == ep_ini + 2 then
      if endpoint_odd == true then -- use endpoints odd only
        return "switch2"
      else
        return "switch3"
      end
    elseif ep == ep_ini + 3 and endpoint_odd == false then
      return "switch4"
    elseif ep == ep_ini + 4 then
      if endpoint_odd == true then -- use endpoints odd only
        return "switch3"
      else
        return "switch5"
      end
    elseif ep == ep_ini + 6 and device:get_manufacturer() == "_TYZB01_vkwryfdr" then
      return "switch5"
    elseif ep == ep_ini + 6 and endpoint_odd == true then -- use endpoints odd only
      return "switch4"
    elseif ep == ep_ini + 5 and endpoint_odd == false then
      return "switch6"
    end 
  end
end

--do_configure
local function do_configure(driver, device)
  print("DEBUG: do_configure called for device:", device.label, "model:", device:get_model())
  
  --print("Device table >>>>>>",utils.stringify_table(device))
  --print("Driver table >>>>>>",utils.stringify_table(driver))

  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
    if device:get_manufacturer() ~= "_TZ3000_fvh3pjaz" 
    and device:get_manufacturer() ~= "_TZ3000_wyhuocal" then   -- devices tutn off after 2 minutes

      -- Configure OnOff interval report
      local interval =  device.preferences.onOffReports
      if  device.preferences.onOffReports == nil then interval = 300 end
      local config ={
        cluster = zcl_clusters.OnOff.ID,
        attribute = zcl_clusters.OnOff.attributes.OnOff.ID,
        minimum_interval = 0,
        maximum_interval = interval,
        data_type = zcl_clusters.OnOff.attributes.OnOff.base_type
      }
      --device:send(zcl_clusters.OnOff.attributes.OnOff:configure_reporting(device, 0, device.preferences.onOffReports))
      device:add_configured_attribute(config)
      device:add_monitored_attribute(config)
    
      device:configure()

      -- Additional one time configuration
      if device:supports_capability(capabilities.energyMeter) or device:supports_capability(capabilities.powerMeter) then
        -- Divisor and multipler for EnergyMeter
        device:send(ElectricalMeasurement.attributes.ACPowerDivisor:read(device))
        device:send(ElectricalMeasurement.attributes.ACPowerMultiplier:read(device))
        -- Divisor and multipler for PowerMeter
        device:send(SimpleMetering.attributes.Divisor:read(device))
        device:send(SimpleMetering.attributes.Multiplier:read(device))
      end

    else
      --device:send(device_management.build_bind_request(device, zcl_clusters.OnOff.ID, driver.environment_info.hub_zigbee_eui):to_endpoint (1))
      --device:send(zcl_clusters.OnOff.attributes.OnOff:configure_reporting(device, 0, 120):to_endpoint (1))
      --device:send(device_management.build_bind_request(device, zcl_clusters.OnOff.ID, driver.environment_info.hub_zigbee_eui):to_endpoint (2))
      --device:send(zcl_clusters.OnOff.attributes.OnOff:configure_reporting(device, 0, 120):to_endpoint (2))
    end
    print("doConfigure performed, transitioning device to PROVISIONED") --23/12/23
    device:try_update_metadata({ provisioning_state = "PROVISIONED" })
    
    if device:get_model() == "lumi.switch.acn047" then
      print("<< Send preferences for Aqara T2 >>")
      if device.preferences.restoreStateLumi ~= nil then
        local value_send = tonumber(device.preferences.restoreStateLumi)
        local data_type = data_types.Uint8
        local cluster_id = 0xFCC0
        local attr_id = 0x0517
        local mfg_code = 0x115F
        device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value_send, mfg_code):to_endpoint (1))
        device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value_send, mfg_code):to_endpoint (2))
      elseif device.preferences.interlockMode ~= nil then
        local value_send = tonumber(device.preferences.interlockMode)
        local value = false
        if value_send == 1 then value = true end
        local data_type = data_types.Boolean
        local cluster_id = 0xFCC0
        local attr_id = 0x02D0
        local mfg_code = 0x115F
        device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value, mfg_code):to_endpoint (1))
        device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value, mfg_code):to_endpoint (2))
      elseif device.preferences.mode ~= nil then
        local value_send = tonumber(device.preferences.mode)
        local data_type = data_types.Uint8
        local cluster_id = 0xFCC0
        local attr_id = 0x0289
        local mfg_code = 0x115F
        device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value_send, mfg_code):to_endpoint (1))
        device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value_send, mfg_code):to_endpoint (2))
      elseif device.preferences.dryPulseTime ~= nil then
        local value_send = device.preferences.dryPulseTime
        local data_type = data_types.Uint16
        local cluster_id = 0xFCC0
        local attr_id = 0x00EB
        local mfg_code = 0x115F
        device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value_send, mfg_code):to_endpoint (1))
        device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value_send, mfg_code):to_endpoint (2))
      end

      device.thread:call_with_delay(3, function(d)
        print("<<< Read Aqara T2 custom Preference attributes >>>")
        local attr_ids = {0x02D0, 0x0289, 0x00EB, 0x0517} 
        device:send(read_attribute_function (device, data_types.ClusterId(0xFCC0), attr_ids))
      end)
    end

    -- Configuration for lumi.switch.acn040 (3-switch with decoupling) - DISABLED
    -- This has been moved to the profile-based initialization in device_init to avoid conflicts
    print("DEBUG: Device model is:", device:get_model())
    -- if device:get_model() == "lumi.switch.acn040" then ... end -- REMOVED: Using profile-based init instead
  end
end

---- Component to endpoint mapping (similar to 4-button driver) ----
local function lumi_component_to_endpoint(device, component_id)
  -- Handle button components
  if component_id == "button1" then return 1 end
  if component_id == "button2" then return 2 end  
  if component_id == "button3" then return 3 end
  
  -- Handle switch components (existing mapping)
  if component_id == "main" then return 1 end
  if component_id == "switch2" then return 2 end
  if component_id == "switch3" then return 3 end
  
  return 1  -- default
end

---- Endpoint to component mapping (similar to 4-button driver) ----
local function lumi_endpoint_to_component(device, endpoint)
  if device.preferences.logDebugPrint == true then
    print("lumi_endpoint_to_component called - endpoint:", endpoint, "profile:", device.profile.name)
  end
  
  -- For button events in decoupled mode, we want to route to button components
  if is_lumi_combined_profile(device) then
    -- Check if the corresponding switch is decoupled
    local is_decoupled = false
    local component_id = nil
    
    if endpoint == 1 then
      is_decoupled = device.preferences.decoupleSwitch1 == "0"
      component_id = is_decoupled and "button1" or "main"
    elseif endpoint == 2 then
      is_decoupled = device.preferences.decoupleSwitch2 == "0"
      component_id = is_decoupled and "button2" or "switch2"
    elseif endpoint == 3 then
      is_decoupled = device.preferences.decoupleSwitch3 == "0"
      component_id = is_decoupled and "button3" or "switch3"
    else
      component_id = "main"
    end
    
    if device.preferences.logDebugPrint == true then
      print("Endpoint", endpoint, "-> component:", component_id, "decoupled:", is_decoupled)
    end
    return component_id
  end
  
  -- Default switch component mapping
  if endpoint == 1 then return "main" end
  if endpoint == 2 then return "switch2" end
  if endpoint == 3 then return "switch3" end
  
  return "main"
end

---device init ----
local function device_init (driver, device)
  print("🚀 DEVICE_INIT START - device_network_id >>>",device.device_network_id)
  print("🚀 DEVICE_INIT START - label >>>",device.label)
  print("🚀 DEVICE_INIT START - model >>>", device:get_model())
  print("🚀 DEVICE_INIT START - manufacturer >>>", device:get_manufacturer())
  print("🚀 DEVICE_INIT START - profile >>>", device.preferences.profile or "nil")
  print("🚀 DEVICE_INIT START - device.profile >>>", device.profile and device.profile.name or "nil")
  print("🚀 FINGERPRINT CHECK - Expected: manufacturer=LUMI, model=lumi.switch.acn040")
  print("parent_device_id >>>",device.parent_device_id)
  print("device.preferences.profileType >>>",device.preferences.profileType)
  
  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
    -- Profile-dependent initialization moved to device_added where profile is available
    print("🚀 DEVICE_INIT: Profile-dependent code moved to device_added - profile is nil here")

      ------ Selected profile & Icon
      for id, value in pairs(device.preferences) do
        if device.preferences.logDebugPrint == true then
          print("<< Preference name: >>", id, "Preference value:", device.preferences[id])
        end
        if id == "changeProfileThreePlug" then
          if device.preferences[id] == "Single" then
            device:try_update_metadata({profile = "three-outlet"})
          else
          device:try_update_metadata({profile = "three-outlet-multi"})
          end
        elseif id == "changeProfileThreeSw" then
          if device.preferences[id] == "Single" then
            device:try_update_metadata({profile = "three-switch"})
          else
            device:try_update_metadata({profile = "three-switch-multi"})
          end
        elseif id == "changeProfileTwoPlug" then
          if device.preferences[id] == "Single" then
            device:try_update_metadata({profile = "two-outlet"})
          else
            device:try_update_metadata({profile = "two-outlet-multi"})
          end
        elseif id == "changeProfileTwoPlugPw" then
          if device.preferences[id] == "Single" then
            device:try_update_metadata({profile = "two-plug-power"})
          else
            device:try_update_metadata({profile = "two-plug-power-multi"})
          end
        elseif id == "changeProfileTwoSwPw" then
          if device.preferences[id] == "Single" then
            device:try_update_metadata({profile = "two-switch-power-energy"})
          else
            device:try_update_metadata({profile = "two-switch-power-energy-multi"})
          end
        elseif id == "changeProfileTwoSwPw1" then
          if device.preferences[id] == "Single" then
            device:try_update_metadata({profile = "two-switch-power-energy-1"})
          else
            device:try_update_metadata({profile = "two-switch-power-energy-multi-1"})
          end
        elseif id == "changeProfileTwoSw" then
          if device.preferences[id] == "Single" then
            device:try_update_metadata({profile = "two-switch"})
          else
            device:try_update_metadata({profile = "two-switch-multi"})
          end
        elseif id == "changeProfileFourSw" then
          if device.preferences[id] == "Single" then
            device:try_update_metadata({profile = "four-switch"})
          else
            device:try_update_metadata({profile = "four-switch-multi"})
          end
        elseif id == "changeProfileFourPlug" then
          if device.preferences[id] == "Single" then
            device:try_update_metadata({profile = "four-outlet"})
          else
            device:try_update_metadata({profile = "four-outlet-multi"})
          end
        elseif id == "changeProfileFiveSw" then
            if device.preferences[id] == "Single" then
            device:try_update_metadata({profile = "five-switch"})
            else
            device:try_update_metadata({profile = "five-switch-multi"})
            end
        elseif id == "changeProfileFivePlug" then
            if device.preferences[id] == "Single" then
              device:try_update_metadata({profile = "five-outlet"})
            else
              device:try_update_metadata({profile = "five-outlet-multi"})
            end
        elseif id == "changeProfileSix" then
          if device.preferences[id] == "Switch" then
            device:try_update_metadata({profile = "six-switch"})
          else
            device:try_update_metadata({profile = "six-outlet"})
          end
        elseif id == "changeProfileLumi" then
          if device.preferences[id] == "multi" then
            device:try_update_metadata({profile = "lumi-two-switch-power-energy-1-multi"})
          else
            device:try_update_metadata({profile = "lumi-two-switch-power-energy-1"})
          end
        end
    end

    --tuyaBlackMagic() {return zigbee.readAttribute(0x0000, [0x0004, 0x000, 0x0001, 0x0005, 0x0007, 0xfffe], [:], delay=200)}
    if device:get_model() ~= "FB56+ZSW1JKJ2.7" and 
      device:get_model()~="FB56+ZSW1IKJ2.5" and 
      device:get_model()~= "FB56+ZSW1HKJ2.5" and
      device:get_model()~="FB56+ZSW1IKJ1.7" and
      device:get_model()~="FB56+ZSW1JKJ2.5" and
      device:get_model()~= "FB56+ZSW1HKJ2.7" then
        print("<<< Read Basic clusters attributes >>>")
        local attr_ids = {0x0004, 0x0000, 0x0001, 0x0005, 0x0007,0xFFFE} 
        device:send(read_attribute_function (device, data_types.ClusterId(0x0000), attr_ids))
    end

    --- special cofigure for this device, read attribute on-off every 120 sec and not configure reports
    if device:get_manufacturer() == "_TZ3000_fvh3pjaz"
     or device:get_manufacturer() == "_TZ3000_wyhuocal" then   -- devices tutn off after 2 minutes

      --- Configure basic cluster, attributte 0x0099 to 0x1
      local data_value = {value = 0x01, ID = 0x20}
      local cluster_id = {value = 0x0000}
      local attr_id = 0x0099
      write.write_attribute_function(device, cluster_id, attr_id, data_value, 1)

      print("<<<<<<<<<<< read attribute 0xFF, 1 & 2 >>>>>>>>>>>>>")
      device:send(zcl_clusters.OnOff.attributes.OnOff:read(device):to_endpoint (0xFF))
      device:send(zcl_clusters.OnOff.attributes.OnOff:read(device):to_endpoint (1))
      device:send(zcl_clusters.OnOff.attributes.OnOff:read(device):to_endpoint (2))
      if device:get_manufacturer() == "_TZ3000_wyhuocal" then
        device:send(zcl_clusters.OnOff.attributes.OnOff:read(device):to_endpoint (3))
      end

      ---- Timers Cancel ------
        for timer in pairs(device.thread.timers) do
          print("<<<<< Cancelando timer >>>>>")
          device.thread:cancel_timer(timer)
        end
      --- Refresh atributte read schedule
      --print("<<<<<<<<<<<<< Timer read attribute >>>>>>>>>>>>>>>>")
      device.thread:call_on_schedule(
      120,
      function ()
        if device:get_manufacturer() == "_TZ3000_fvh3pjaz" 
        or device:get_manufacturer() == "_TZ3000_wyhuocal" then    -- devices tutn off after 2 minutes
          if device.preferences.logDebugPrint == true then
            print("<<< Timer read attribute >>>")
          end
          device:send(zcl_clusters.OnOff.attributes.OnOff:read(device):to_endpoint (1))
          device:send(zcl_clusters.OnOff.attributes.OnOff:read(device):to_endpoint (2))
          if device:get_manufacturer() == "_TZ3000_wyhuocal" then
            device:send(zcl_clusters.OnOff.attributes.OnOff:read(device):to_endpoint (3))
          end
        end
      end,
      'Refresh schedule')
    --end
    else
      -- Configure OnOff interval report
      local interval =  device.preferences.onOffReports
      if  device.preferences.onOffReports == nil then interval = 300 end
      local config ={
        cluster = zcl_clusters.OnOff.ID,
        attribute = zcl_clusters.OnOff.attributes.OnOff.ID,
        minimum_interval = 0,
        maximum_interval = interval,
        data_type = zcl_clusters.OnOff.attributes.OnOff.base_type
      }
      --device:send(zcl_clusters.OnOff.attributes.OnOff:configure_reporting(device, 0, device.preferences.onOffReports))
      device:add_configured_attribute(config)
      device:add_monitored_attribute(config)
    end

    if device:get_latest_state("main", signal_Metrics.ID, signal_Metrics.signalMetrics.NAME) == nil then
      device:emit_event(signal_Metrics.signalMetrics({value = "Waiting Zigbee Message"}, {visibility = {displayed = false }}))
    end

    if device:get_model() ~= "2GBatteryDimmer50AU" then
      local last_level_1 = device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME)
      if last_level_1 == nil then last_level_1 = 0 end
      last_level_1 = math.floor(last_level_1 * 254 / 100)
      device:set_field("last_level_1", last_level_1)
      local last_level_2 = device:get_latest_state("switch2", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME)
      if last_level_2 == nil then last_level_2 = 0 end
      last_level_2 = math.floor(last_level_2 * 254 / 100)
      device:set_field("last_level_2", last_level_2)
    end

    --config = {
      --cluster = zcl_clusters.Basic.ID,
      --attribute = zcl_clusters.Basic.attributes.ApplicationVersion.ID,
      --minimum_interval = 0xFFFF,
      --maximum_interval = 0xFFFF,
      --data_type = data_types.Uint8,
      --reportable_change = 0xFF,
    --}
    --device:add_configured_attribute(config)
   
    --[[ local config = {
      cluster = 0x0000,
      attribute = 0xFFE2,
      minimum_interval = 0x0,
      maximum_interval = 0x0,
      data_type = data_types.Uint8,
      reportable_change = 0xFF,
    }
    device:add_configured_attribute(config)
    device:send(zcl_clusters.Basic.attributes.ZCLVersion:configure_reporting(device, 0xFFFE, 0xFFFE ,0xFF, data_types.Uint8))
    device:send(zcl_clusters.Basic.attributes.ApplicationVersion:configure_reporting(device, 0xFFFE, 0xFFFE ,0xFF, data_types.Uint8))

    device.thread:call_with_delay(4, function(d)
      device:configure()
    end)]]
    
    -- Debug: Show actual profile being used (UNCONDITIONAL)
    print("DEBUG: Device model:", device:get_model())
    print("DEBUG: Device profile name:", device.profile and device.profile.name or "nil")
    print("DEBUG: Expected profile: lumi_three_switch_button_combined")
    
    -- Setup decoupling for lumi combined profile - moved from do_configure to ensure it always runs
    if is_lumi_combined_profile(device) then
      print("DEBUG: MATCHED lumi combined profile - Running decoupling configuration in device_init!")
      device.thread:call_with_delay(5, function(d)
        print("<< Send preferences for Aqara 3-Switch Decouple (from device_init) >>")
        
        -- Set decoupling preferences if they exist (endpoints 1,2,3)
        if device.preferences.decoupleSwitch1 ~= nil then
          local value_send = tonumber(device.preferences.decoupleSwitch1)  -- 0=decoupled, 1=coupled (control_relay)
          local data_type = data_types.Uint8
          local cluster_id = 0xFCC0
          local attr_id = 0x0200  -- Operation mode attribute (exactly as zigbee-herdsman-converters)
          local mfg_code = 0x115F
          device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value_send, mfg_code):to_endpoint (1))
        end
        
        if device.preferences.decoupleSwitch2 ~= nil then
          local value_send = tonumber(device.preferences.decoupleSwitch2)  -- 0=decoupled, 1=coupled (control_relay)
          local data_type = data_types.Uint8
          local cluster_id = 0xFCC0
          local attr_id = 0x0200  -- Operation mode attribute (exactly as zigbee-herdsman-converters)
          local mfg_code = 0x115F
          device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value_send, mfg_code):to_endpoint (2))
        end
        
        if device.preferences.decoupleSwitch3 ~= nil then
          local value_send = tonumber(device.preferences.decoupleSwitch3)  -- 0=decoupled, 1=coupled (control_relay)
          local data_type = data_types.Uint8
          local cluster_id = 0xFCC0
          local attr_id = 0x0200  -- Operation mode attribute (exactly as zigbee-herdsman-converters)
          local mfg_code = 0x115F
          device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, value_send, mfg_code):to_endpoint (3))
        end

        -- Configure device for button events (based on zigbee-herdsman-converters)
        device.thread:call_with_delay(2, function(d)
          print("<<< Configuring Aqara 3-Switch for button events >>>")
          -- Set "event" mode to enable button events
          local data_type = data_types.Uint8
          local cluster_id = 0xFCC0
          local attr_id = 0x0009  -- mode attribute
          local mfg_code = 0x115F
          local mode_value = 1  -- event mode
          device:send(write.custom_write_attribute(device, cluster_id, attr_id, data_type, mode_value, mfg_code):to_endpoint(1))
          
          -- Enable "multiple clicks" mode (based on herdsman converters)
          device.thread:call_with_delay(1, function(d)
            print("<<< Enabling multiple clicks mode >>>")
            local multi_click_attr = 0x0125  -- 293 decimal = 0x0125 hex
            local multi_click_value = 2  -- enable multiple clicks
            device:send(write.custom_write_attribute(device, cluster_id, multi_click_attr, data_type, multi_click_value, mfg_code):to_endpoint(1))
          end)
        end)

        -- Read current decoupling states after configuration
        device.thread:call_with_delay(5, function(d)
          print("<<< Read Aqara 3-Switch decoupling attributes (from device_init) >>>")
          -- Read decoupling attribute (0x0200) exactly as zigbee-herdsman-converters
          local attr_ids = {0x0200} 
          device:send(read_attribute_function (device, data_types.ClusterId(0xFCC0), attr_ids))
        end)
      end)
    end
    
    -- Component capabilities initialization moved to device_added where profile is available
  end
end

local function driver_Switched(driver,device)
  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
    device.thread:call_with_delay(3, function(d) --30/03/24
      do_configure(driver, device)
    end, "configure")
  end
end

------ do_configure device
local function driver_Switched_old(driver,device)

  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)

    --device:refresh() --- removed 18-sep-23
    if device:get_manufacturer() ~= "_TZ3000_fvh3pjaz"  -- devices tutn off after 2 minutes
      and device:get_manufacturer() ~= "_TZ3000_wyhuocal"
      and device:get_manufacturer() ~= nil then

      --tuyaBlackMagic() {return zigbee.readAttribute(0x0000, [0x0004, 0x000, 0x0001, 0x0005, 0x0007, 0xfffe], [:], delay=200)}
      if (device:get_model() ~= "FB56+ZSW1JKJ2.7" and 
        device:get_model()~="FB56+ZSW1IKJ2.5" and 
        device:get_model()~= "FB56+ZSW1HKJ2.5" and
        device:get_model()~="FB56+ZSW1IKJ1.7" and
        device:get_model()~="FB56+ZSW1JKJ2.5" and
        device:get_model()~= "FB56+ZSW1HKJ2.7") then
          print("<<< Read Basic clusters attributes >>>")
          local attr_ids = {0x0004, 0x0000, 0x0001, 0x0005, 0x0007,0xFFFE} 
          device:send(read_attribute_function (device, data_types.ClusterId(0x0000), attr_ids))
      end

      -- Configure OnOff interval report
      local interval =  device.preferences.onOffReports
      if  device.preferences.onOffReports == nil then interval = 300 end
      local config ={
        cluster = zcl_clusters.OnOff.ID,
        attribute = zcl_clusters.OnOff.attributes.OnOff.ID,
        minimum_interval = 0,
        maximum_interval = interval,
        data_type = zcl_clusters.OnOff.attributes.OnOff.base_type
      }
      --device:send(zcl_clusters.OnOff.attributes.OnOff:configure_reporting(device, 0, device.preferences.onOffReports))
      device:add_configured_attribute(config)
      device:add_monitored_attribute(config)

      --device:configure()
      device.thread:call_with_delay(2, function(d) --23/12/23
        device:configure()
        --print("doConfigure performed, transitioning device to PROVISIONED")
        --device:try_update_metadata({ provisioning_state = "PROVISIONED" })
      end, "configure")

      -- Additional one time configuration
      if device:supports_capability(capabilities.energyMeter) or device:supports_capability(capabilities.powerMeter) then
        -- Divisor and multipler for EnergyMeter
        device:send(ElectricalMeasurement.attributes.ACPowerDivisor:read(device))
        device:send(ElectricalMeasurement.attributes.ACPowerMultiplier:read(device))
        -- Divisor and multipler for PowerMeter
        device:send(SimpleMetering.attributes.Divisor:read(device))
        device:send(SimpleMetering.attributes.Multiplier:read(device))
      end
    end
  end
end 

---- switch_All_On_Off_handler
local function switch_All_On_Off_handler(driver, device, command)
  if device.preferences.logDebugPrint == true then
    print("command >>>>>", command)
    print("command.args.value >>>>>", command.args.value)
  end
  local ep_init = 1
  local state = ""
  local attr = capabilities.switch.switch
  if command ~= "All On" and  command ~= "All Off" then    ---- commad with this values is from child device command
    state = command.args.value
    device:emit_event(switch_All_On_Off.switchAllOnOff(state))
    ep_init = device:get_endpoint_for_component_id(command.component)
  else
    state = command
  end

  for id, value in pairs(device.preferences) do
   if id == "changeProfileSix" then
    if state == "All Off" then
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init))
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 1))
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 2))
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 3))
      if device:get_manufacturer() == "_TYZB01_vkwryfdr" then
        device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 6))
      else
        device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 4))
      end
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 5))
    else
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init))
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 1))
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 2))
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 3))
      if device:get_manufacturer() == "_TYZB01_vkwryfdr" then
        device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 6))
      else
        device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 4))
      end
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 5))
    end
  elseif id == "changeProfileFivePlug" or id == "changeProfileFiveSw" then
      if state == "All Off" then
        device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init))
        device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 1))
        device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 2))
        device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 3))
        if device:get_manufacturer() == "_TYZB01_vkwryfdr" then
          device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 6))
        else
          device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 4))
        end
      else
        device:send(OnOff.server.commands.On(device):to_endpoint(ep_init))
        device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 1))
        device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 2))
        device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 3))
        if device:get_manufacturer() == "_TYZB01_vkwryfdr" then
          device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 6))
        else
          device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 4))
        end
      end
   elseif id == "changeProfileFourPlug" or id == "changeProfileFourSw" then
    if state == "All Off" then
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init))
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 1))
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 2))
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 3))
    else
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init))
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 1))
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 2))
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 3))
    end
   --elseif id == "changeProfileThreePlug" or id == "changeProfileThreeSw" then
   elseif id == "switch3Child" and device.preferences.switch4Child == nil then
    if state == "All Off" then
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init))
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 1))
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 2))
    else
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init))
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 1))
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 2))
    end
   --elseif id == "changeProfileTwoPlug" or id == "changeProfileTwoSw" then
   elseif (id == "switch2Child" and device.preferences.switch3Child == nil) or
    (id == "switch2LevelChild" and device.preferences.switch3Child == nil) then
    if state == "All Off" then
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init))
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 1))
    else
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init))
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 1))
    end  
   end
  end
end

--- Command on handler ---- 
local function on_handler(driver, device, command)
  if device.preferences.logDebugPrint == true then
    print("<<<< On command Handler >>>>")
  end
  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
    if device:get_model() ~= "2GBatteryDimmer50AU" then
      device:send_to_component(command.component, zcl_clusters.OnOff.server.commands.On(device))
    else
      local endpoint = device:get_endpoint_for_component_id(command.component)
      device:emit_event_for_endpoint(endpoint, capabilities.switch.switch.on())

      --- Set all_switches_status capability status
      device.thread:call_with_delay(2, function(d)
        all_switches_status(driver, device)
      end)
    end
  else
    local parent_device = device:get_parent_device()
    if parent_device.preferences.logDebugPrint == true then
      print("<<< parent_device_id >>>", parent_device)
    end
    device:emit_event(capabilities.switch.switch.on())

    local component = device.parent_assigned_child_key
    if component == "main" then
      switch_All_On_Off_handler(driver, parent_device, "All On")
    else
      if parent_device:get_model() ~= "2GBatteryDimmer50AU" then
        -- send comamd On to parent device
        parent_device:send_to_component(component, OnOff.server.commands.On(parent_device))
      else
        local endpoint = parent_device:get_endpoint_for_component_id(command.component)
        parent_device:emit_event_for_endpoint(endpoint, capabilities.switch.switch.on())
      end
    end
  end
end

--- Command off handler ----
local function off_handler(driver, device, command)
  if device.preferences.logDebugPrint == true then
    print("<<<< Off command Handler >>>>")
  end
  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
    if device:get_model() ~= "2GBatteryDimmer50AU" then
      device:send_to_component(command.component, zcl_clusters.OnOff.server.commands.Off(device))
    else
      local endpoint = device:get_endpoint_for_component_id(command.component)
      device:emit_event_for_endpoint(endpoint, capabilities.switch.switch.off())

      --- Set all_switches_status capability status
      device.thread:call_with_delay(2, function(d)
        all_switches_status(driver, device)
      end)
    end
  else
    local parent_device = device:get_parent_device()
    if parent_device.preferences.logDebugPrint == true then
      print("<<< parent_device_id >>>", parent_device)
    end
    device:emit_event(capabilities.switch.switch.off())

    local component = device.parent_assigned_child_key
    if component == "main" then
      switch_All_On_Off_handler(driver, parent_device, "All Off")
    else
      if parent_device:get_model() ~= "2GBatteryDimmer50AU" then
        -- send comamd Off to parent device
        parent_device:send_to_component(component, OnOff.server.commands.Off(parent_device))
      else
        local endpoint = parent_device:get_endpoint_for_component_id(command.component)
        parent_device:emit_event_for_endpoint(endpoint, capabilities.switch.switch.off())
      end
    end
  end
end

--- read zigbee attribute OnOff messages ----
local function on_off_attr_handler(driver, device, value, zb_rx)
  -- 🚀 PROFILE DEBUG - This handler IS being called!
  print("🚀 ON_OFF_HANDLER - model:", device:get_model())
  print("🚀 ON_OFF_HANDLER - profile:", device.preferences.profile or "nil")
  print("🚀 ON_OFF_HANDLER - device.profile:", device.profile and device.profile.name or "nil") 
  print("🚀 ON_OFF_HANDLER - is_lumi_combined:", is_lumi_combined_profile(device))
  
  -- 🔧 MANUAL INITIALIZATION - Since device_added didn't run but profile detection works
  if is_lumi_combined_profile(device) and device.network_type ~= "DEVICE_EDGE_CHILD" then
    -- Check if initialization already happened by testing a device field
    local needs_init = not device:get_field("lumi_button_init")
    
    if needs_init then
      print("🚀 MANUAL INITIALIZATION: Setting up Lumi button capabilities...")
      -- Set component mapping 
      device:set_component_to_endpoint_fn(lumi_component_to_endpoint)
      device:set_endpoint_to_component_fn(lumi_endpoint_to_component)
      
      -- Initialize button capabilities (now with proper endpoint approach)
      update_component_capabilities(device)
      
      -- Mark as initialized to prevent future runs
      device:set_field("lumi_button_init", true, {persist = true})
      
      print("🚀 MANUAL INITIALIZATION: Complete!")
    end
  end
  
  if device.preferences.logDebugPrint == true then
    print ("function: on_off_attr_handler")
  end

  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)

    -- this Aurora model reponse to set indicator led level then not emit on-off event
    if device:get_model() == "DoubleSocket50AU" then
      --print("<< set-led >>", device:get_field("set-led"))
      if device:get_field("set-led") == "yes" then
        device:set_field("set-led", "reset-on-off")
        return
      end
    end

    -- emit signal metrics
    signal.metrics(device, zb_rx)

    local src_endpoint = zb_rx.address_header.src_endpoint.value
    local attr_value = value.value
    if device.preferences.logDebugPrint == true then
      print ("src_endpoint =", zb_rx.address_header.src_endpoint.value , "value =", value.value)
    end

    --- Emit event from zigbee message recived
    if attr_value == false or attr_value == 0 then
      if device:get_model() ~= "2GBatteryDimmer50AU" then
        device:emit_event_for_endpoint(src_endpoint, capabilities.switch.switch.off())
      else
        device:emit_event_for_endpoint(src_endpoint, capabilities.switch.switch.on())
      end
    elseif attr_value == true or attr_value == 1 then
      if device:get_model() ~= "2GBatteryDimmer50AU" then
        device:emit_event_for_endpoint(src_endpoint, capabilities.switch.switch.on())
      else
        device:emit_event_for_endpoint(src_endpoint, capabilities.switch.switch.off())
      end
    end

    -- emit event for child devices
    local component = device:get_component_id_for_endpoint(src_endpoint)
    local child_device = device:get_child_by_parent_assigned_key(component)
    if child_device ~= nil and component ~= "main" then
      if attr_value == false or attr_value == 0 then
        child_device:emit_event(capabilities.switch.switch.off())
      elseif attr_value == true or attr_value == 1 then
        child_device:emit_event(capabilities.switch.switch.on())
      end
    end

    --- Set all_switches_status capability status
    device.thread:call_with_delay(2, function(d)
      all_switches_status(driver, device)
    end)
  else

  end
end


---- Get button component ID for endpoint ----
local function endpoint_to_button_component(device, endpoint)
  if not is_lumi_combined_profile(device) then
    return nil
  end
  
  if endpoint == 1 then
    return "button1"
  elseif endpoint == 2 then
    return "button2" 
  elseif endpoint == 3 then
    return "button3"
  end
  return nil
end

---- Map button event code to action based on device profile (like herdsman converters) ----
local function map_button_event(code, device)
  -- Button mappings for different profiles
  -- Event codes: 1=single press, 2=double press, 3=triple press
  local button_mappings = {
    ["lumi-three-switch-button-combined"] = {
      [1] = "pushed",    -- Single press
      [2] = "double",    -- Double press  
      [3] = "triple"       -- Triple press (not supported in our profile)
    }
    -- Add more profiles as needed:
    -- ["4-button-battery"] = {
    --   [1] = "pushed",
    --   [2] = "double", 
    --   [3] = "held"
    -- }
  }
  
  local profile_name = device.profile and device.profile.name or "unknown"
  
  if button_mappings[profile_name] and button_mappings[profile_name][code] then
    return button_mappings[profile_name][code]
  end
  
  if device.preferences.logDebugPrint == true then
    print("Unknown button event code:", code, "for profile:", profile_name)
  end
  
  return nil -- Unknown event
end

---- Handle button events from manufacturer cluster (adapted from 4-button driver approach) ----
-- Note: Button identifiers 41,42,43 (Herdsman style) vs Event codes 1,2,3 (press types)
-- - Endpoint identifies which button (1, 2, 3)
-- - Event codes in ZCL body identify press type: 1=single, 2=double, 3=triple
local function handle_lumi_button_event_from_cluster(driver, device, zb_rx)
  if not is_lumi_combined_profile(device) then
    return
  end
  
  local src_endpoint = zb_rx.address_header.src_endpoint.value
  local button_component_id = endpoint_to_button_component(device, src_endpoint)
  
  if device.preferences.logDebugPrint == true then
    print("Button event from cluster - endpoint:", src_endpoint, "component:", button_component_id)
    print("Raw ZCL body:", zb_rx.body.zcl_body and tostring(zb_rx.body.zcl_body) or "nil")
  end
  
  -- Check if this switch is in decoupled mode
  local is_decoupled = false
  if src_endpoint == 1 then
    is_decoupled = device.preferences.decoupleSwitch1 == "0"
  elseif src_endpoint == 2 then
    is_decoupled = device.preferences.decoupleSwitch2 == "0"
  elseif src_endpoint == 3 then
    is_decoupled = device.preferences.decoupleSwitch3 == "0"
  end
  
  if not is_decoupled then
    if device.preferences.logDebugPrint == true then
      print("Switch not in decoupled mode, ignoring button event")
    end
    return  -- Only handle button events for decoupled switches
  end
  
  -- Extract button event code from ZCL body (like 4-button driver approach)
  -- Event codes: 1=single press, 2=double press, 3=triple press
  local event_code = nil
  if zb_rx.body and zb_rx.body.zcl_body then
    local zcl_body_str = tostring(zb_rx.body.zcl_body)
    if zcl_body_str then
      -- Look for event code in ZCL body (pattern may vary from 4-button driver)
      -- Try pattern like "GenericBody: 0X" first (4-button style)
      event_code = zcl_body_str:match("GenericBody:%s*0(%d)")
      if event_code then
        event_code = tonumber(event_code)
      else
        -- Try direct digit pattern for Lumi devices
        event_code = zcl_body_str:match("GenericBody:%s*(%d)")
        if event_code then
          event_code = tonumber(event_code)
        end
      end
    end
  end
  
  if device.preferences.logDebugPrint == true then
    print("Extracted event code:", event_code)
  end
  
  -- Decode button action using profile-based mapping (codes: 41, 42, 43)
  local button_action = nil
  if event_code then
    button_action = map_button_event(event_code, device)
  end
  
  if device.preferences.logDebugPrint == true and button_action then
    print("Mapped button code", event_code, "to action:", button_action)
  end
  
  -- Send button event using emit_component_event with correct button component
  if button_component_id and button_action then
    -- Use emit_component_event instead of emit_event_for_endpoint since device.profile is nil
    device:emit_component_event(button_component_id, button.button(button_action))
    if device.preferences.logDebugPrint == true then
      print("Button event '" .. button_action .. "' sent to component:", button_component_id)
    end
  end
end

---- Handle button events from manufacturer-specific cluster (fallback) ----
local function handle_lumi_button_event(driver, device, zb_rx)
  if not is_lumi_combined_profile(device) then
    return
  end
  
  local src_endpoint = zb_rx.address_header.src_endpoint.value
  local button_component_id = endpoint_to_button_component(device, src_endpoint)
  
  if device.preferences.logDebugPrint == true then
    print("Lumi button event (0xFCC0) - endpoint:", src_endpoint, "button component:", button_component_id)
    print("Raw message body:", zb_rx.body)
  end
  
  -- Check if this switch is in decoupled mode
  local is_decoupled = false
  if src_endpoint == 1 then
    is_decoupled = device.preferences.decoupleSwitch1 == "0"
  elseif src_endpoint == 2 then
    is_decoupled = device.preferences.decoupleSwitch2 == "0"
  elseif src_endpoint == 3 then
    is_decoupled = device.preferences.decoupleSwitch3 == "0"
  end
  
  if not is_decoupled then
    return  -- Only handle button events for decoupled switches
  end
  
  -- For manufacturer cluster, emit generic push (fallback)
  if button_component_id then
    local button_component = nil
    if button_component_id == "button1" then
      button_component = device.profile.components.button1
    elseif button_component_id == "button2" then
      button_component = device.profile.components.button2
    elseif button_component_id == "button3" then
      button_component = device.profile.components.button3
    end
    
    if button_component then
      device:emit_component_event(button_component, button.button("pushed"))
      if device.preferences.logDebugPrint == true then
        print("Fallback button event 'pushed' sent to component:", button_component_id)
      end
    end
  end
end


--- do_added
local function do_added(driver, device)
  
  -- 🚀 PROFILE SHOULD BE AVAILABLE NOW! Check after profile assignment
  print("🚀 DO_ADDED - device_network_id >>>",device.device_network_id)
  print("🚀 DO_ADDED - model >>>", device:get_model())
  print("🚀 DO_ADDED - profile >>>", device.preferences.profile or "nil")
  print("🚀 DO_ADDED - device.profile >>>", device.profile and device.profile.name or "nil")
  
  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NOT Child device)
    -- Handle main device profile-dependent initialization
    if is_lumi_combined_profile(device) then
      print("🚀 LUMI COMBINED PROFILE DETECTED! Initializing button capabilities...")
      
      -- Set component-to-endpoint mapping functions (like 4-button driver)  
      device:set_component_to_endpoint_fn(lumi_component_to_endpoint)
      device:set_endpoint_to_component_fn(lumi_endpoint_to_component)
      
      -- Initialize button capabilities now that profile is available
      update_component_capabilities(device)
      
      print("🚀 LUMI initialization complete!")
    else
      print("🚀 NOT LUMI COMBINED PROFILE - using default mapping")
      -- Default mapping for other devices
      device:set_component_to_endpoint_fn(component_to_endpoint)
      device:set_endpoint_to_component_fn(endpoint_to_component)
    end
  end

  if device.network_type == "DEVICE_EDGE_CHILD" then  ---- device (is Child device)
    print("Adding EDGE:CHILD device...")

    local component = device.parent_assigned_child_key
    local parent_device = device:get_parent_device()

    if component == "main" then
      if parent_device:get_latest_state(component, switch_All_On_Off.ID, switch_All_On_Off.switchAllOnOff.NAME) == "All On" then
        device:emit_event(capabilities.switch.switch.on())
      else
        device:emit_event(capabilities.switch.switch.off())
      end
    else
      if parent_device:get_latest_state(component, capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        device:emit_event(capabilities.switch.switch.on())
      else
        device:emit_event(capabilities.switch.switch.off())
      end
      if device.preferences.profileType == "level" then
        print("device.preferences.profileType >>>",device.preferences.profileType)
        local child_level = parent_device:get_latest_state(component, capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME)
        device:emit_event(capabilities.switchLevel.level(math.floor((child_level / 254.0 * 100) + 0.5)))       
      end
    end
  end
end

--- default_response_handler
local function default_response_handler(driver, device, zb_rx)
  if device.preferences.logDebugPrint == true then
    print("<<<<<< default_response_handler >>>>>>")
  end 

  -- this Aurora model reponse to set indicator led level then not emit on-off event
  if device:get_model() == "DoubleSocket50AU" then
    --print("<< set-led >>", device:get_field("set-led"))
    if device:get_field("set-led") == "yes" then
      device:set_field("set-led", "reset-default")
      return
    end
  end
  -- emit signal metrics
  signal.metrics(device, zb_rx)

  local status = zb_rx.body.zcl_body.status.value

  local attr_value = false
  if status == Status.SUCCESS then
    local cmd = zb_rx.body.zcl_body.cmd.value
    local event = nil

    if cmd == zcl_clusters.OnOff.server.commands.On.ID then
      event = capabilities.switch.switch.on()
      attr_value = true
    elseif cmd == zcl_clusters.OnOff.server.commands.Off.ID then
      event = capabilities.switch.switch.off()
    end

    if event ~= nil then
      device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, event)
    end
  end

  -- emit event for child devices
  local component = device:get_component_id_for_endpoint(zb_rx.address_header.src_endpoint.value)
  local child_device = device:get_child_by_parent_assigned_key(component)
  if child_device ~= nil and component ~= "main" then
    if attr_value == false then
      child_device:emit_event(capabilities.switch.switch.off())
    else
      child_device:emit_event(capabilities.switch.switch.on())
    end
  end

  --- Set all_switches_status capability status
  device.thread:call_with_delay(2, function(d)
    all_switches_status(driver, device)
  end)
end

  --- switch_level_handler
  local function switch_level_handler(self,device,command)
    if device.preferences.logDebugPrint == true then
      print("handler_Level >>>>>>>>>>>>>>",command.args.level)
    end

    local on_Level = command.args.level

    if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
      if device:get_model() ~= "2GBatteryDimmer50AU" then
        -- this device uses level cluster to set led indicators level 
        -- and need does not update the on-off attribute handler state
        if device:get_model() == "DoubleSocket50AU" then 
          device:set_field("set-led", "yes")
        end
        device:send_to_component(command.component, zcl_clusters.Level.server.commands.MoveToLevelWithOnOff(device, math.floor(on_Level/100.0 * 254), 0xFFFF))

      
        -- emit event for child devices
        local component = command.component
        local child_device = device:get_child_by_parent_assigned_key(component)
        if child_device ~= nil and component ~= "main" then
          if child_device.preferences.profileType == "level" then
            child_device:emit_event(capabilities.switchLevel.level(on_Level))
          end
        end
      else
        local endpoint = device:get_endpoint_for_component_id(command.component)
        --device:emit_event_for_endpoint(endpoint, capabilities.switch.switch.on())
        device:emit_event_for_endpoint(endpoint, capabilities.switchLevel.level(on_Level))
      end
    else
      device:emit_event(capabilities.switchLevel.level(on_Level))

      local component = device.parent_assigned_child_key
      local parent_device = device:get_parent_device()

      -- send comamd level to parent device
      if component ~= "main" then
        if parent_device:get_model() ~= "2GBatteryDimmer50AU" then
          parent_device:send_to_component(component, zcl_clusters.Level.commands.MoveToLevelWithOnOff(parent_device, math.floor(on_Level/100.0 * 254), 0xFFFF))
        else
          local endpoint = parent_device:get_endpoint_for_component_id(command.component)
          --parent_device:emit_event_for_endpoint(endpoint, capabilities.switch.switch.on())
          parent_device:emit_event_for_endpoint(endpoint, capabilities.switchLevel.level(on_Level))
        end
      end
    end
  end

---- Level response emit event
local function level_attr_handler(driver, device, value, zb_rx)
  if device.preferences.logDebugPrint == true then
    print("<<<< emit Level >>>>")
  end

  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.switchLevel.level(math.floor((value.value / 254.0 * 100) + 0.5)))
  
    -- emit event for child devices
    local component = device:get_component_id_for_endpoint(zb_rx.address_header.src_endpoint.value)
    local child_device = device:get_child_by_parent_assigned_key(component)
    if child_device ~= nil and component ~= "main" then
      if child_device.preferences.profileType == "level" then
        child_device:emit_event(capabilities.switchLevel.level(math.floor((value.value / 254.0 * 100) + 0.5)))
      end
    end
  else

  end
end

-- step_command_handler for aurora 2GBatteryDimmer50AU battery dimmer
local function step_command_handler (driver, device, zb_rx)
    local endpoint = zb_rx.address_header.src_endpoint.value

    local zb_message = zb_rx
    local step_command = zb_message.body.zcl_body
    --Print message command with function utils.stringify_table(step_command)
    --print("step message >>>>>>",utils.stringify_table(step_command))

    local component = device:get_component_id_for_endpoint(endpoint)

    local level = device:get_field("last_level_1")
    if component == "switch2" then
      level = device:get_field("last_level_2")
    end
    if level == nil then level = 0 end
    --level = math.floor(level * 254 / 100)
    local direction = step_command.step_mode.value
    local step_level = step_command.step_size.value
    if device.preferences.logDebugPrint == true then
      print("<<< src Endpoint", endpoint)
      print("<<< direction", direction)
      print("<<< step_level", step_level)
    end

    if direction == 1 then
      step_level = step_level * -1
    end

    level = level + step_level
    if level > 254 then
      level = 254
    elseif level < 0 then
      level = 0
    end
    if component == "main" then
      device:set_field("last_level_1", level)
    elseif component == "switch2" then
      device:set_field("last_level_2", level)
    end
    device:emit_event_for_endpoint(endpoint, capabilities.switchLevel.level(math.floor((level / 254.0 * 100) + 0.5)))

    -- emit event for child devices
    local child_device = device:get_child_by_parent_assigned_key(component)
    if child_device ~= nil and component ~= "main" then
      if child_device.preferences.profileType == "level" then
        child_device:emit_event(capabilities.switchLevel.level(math.floor((level / 254.0 * 100) + 0.5)))
      end
    end
end

---- Driver configure ---------
local zigbee_outlet_driver_template = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.switchLevel,
    capabilities.powerMeter,
    capabilities.energyMeter,
    capabilities.refresh,
    capabilities.battery,
    button
  },
  lifecycle_handlers = {
    init = device_init,
    driverSwitched = driver_Switched,
    infoChanged = do_preferences,
    doConfigure = do_configure,
    added = do_added,
  },
  zigbee_handlers = {
    cluster = {
      [zcl_clusters.Level.ID] = {
        [zcl_clusters.Level.server.commands.Step.ID] = step_command_handler
      },
      -- Handle manufacturer-specific cluster for button events
      [0xFCC0] = {
        [zcl_global_commands.REPORT_ATTRIBUTE_ID] = handle_lumi_button_event,
        -- Add more command IDs if needed for button events
        [0xFD] = handle_lumi_button_event_from_cluster,  -- Similar to 4-button driver approach
      },
    },
    global = {
     [zcl_clusters.OnOff.ID] = {
        [zcl_global_commands.DEFAULT_RESPONSE_ID] = default_response_handler
      }
    },
    attr = {
      [zcl_clusters.OnOff.ID] = {
         [zcl_clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler
     },
     [zcl_clusters.Level.ID] = {
        [zcl_clusters.Level.attributes.CurrentLevel.ID] = level_attr_handler
      },

   }
},
capability_handlers = {
  [capabilities.switch.ID] = {
    [capabilities.switch.commands.on.NAME] = on_handler,
    [capabilities.switch.commands.off.NAME] = off_handler
  },
  [switch_All_On_Off.ID] = {
    [switch_All_On_Off.commands.setSwitchAllOnOff.NAME] = switch_All_On_Off_handler,
  },
  [capabilities.switchLevel.ID] = {
    [capabilities.switchLevel.commands.setLevel.NAME] = switch_level_handler
  },
},
--health_check = false
}

defaults.register_for_default_handlers(zigbee_outlet_driver_template, zigbee_outlet_driver_template.supported_capabilities)
local zigbee_outlet = ZigbeeDriver("Zigbee_Multi_Switch", zigbee_outlet_driver_template)
zigbee_outlet:run()