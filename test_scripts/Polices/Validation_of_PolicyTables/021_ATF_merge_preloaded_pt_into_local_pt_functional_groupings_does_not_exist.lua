---------------------------------------------------------------------------------------------
-- Requirement summary:
-- [Policies] Merging rules for "functional_groupings" section - does not exist in LocalPT and exists in PreloadedPT
--
-- Description:
-- Check of merging rules for "functional_groupings" section in case when does not in LocalPT and exists in PreloadedPT
-- 1. Used preconditions
-- Delete files and policy table from previous ignition cycle if any
-- Start SDL with PreloadedPT json file with "preloaded_date" parameter and "functional_group_name" section with 3 groups
-- 2. Performed steps
-- Stop SDL
-- Start SDL with corrected PreloadedPT json file with "preloaded_date" parameter with bigger value
-- and "functional_group_name" section with 4 groups (the same that were in precondition + 1 new)
--
-- Expected result:
-- SDL must add the "functional_group_name" sectionat LocalPT without changes (with all 4 groups)
---------------------------------------------------------------------------------------------

--[[ General configuration parameters ]]
Test = require('connecttest')
local config = require('config')
require('user_modules/AppTypes')
config.defaultProtocolVersion = 2

--[[ Required Shared libraries ]]
local commonFunctions = require ('user_modules/shared_testcases/commonFunctions')
local commonSteps = require ('user_modules/shared_testcases/commonSteps')
local json = require("modules/json")

--[[ Local Variables ]]
local TESTED_DATA = {
  preloaded_date = {"1988-12-01","2015-05-02"},
  {
    app_policies =
    {
      default =
      {
        keep_context = false,
        steal_focus = false,
        priority = "NONE",
        default_hmi = "NONE",
        groups = {"Base-4"}
      },
      ["007"] =
      {
        keep_context = true,
        steal_focus = false,
        priority = "NORMAL",
        default_hmi = "NONE",
        groups = {"Base-4"}
      },
      device =
      {
        keep_context = false,
        steal_focus = false,
        priority = "NONE",
        default_hmi = "NONE",
        groups = {"Base-6", "Base-4"}
      },
      pre_DataConsent =
      {
        keep_context = false,
        steal_focus = false,
        priority = "NONE",
        default_hmi = "NONE",
        groups = {"Base-6"}
      }
    }
  },
  {
    ["Location-1"] = {
      user_consent_prompt = "Location",
      rpcs = {
        GetVehicleData = {
          hmi_levels = {"BACKGROUND",
            "FULL",
            "LIMITED"
          },
          parameters = {"gps", "speed"}
        },
        OnVehicleData = {
          hmi_levels = {"BACKGROUND",
            "FULL",
            "LIMITED"
          },
          parameters = {"gps", "speed"}
        },
        SubscribeVehicleData = {
          hmi_levels = {"BACKGROUND",
            "FULL",
            "LIMITED"
          },
          parameters = {"gps", "speed"}
        },
        UnsubscribeVehicleData = {
          hmi_levels = {"BACKGROUND",
            "FULL",
            "LIMITED"
          },
          parameters = {"gps", "speed"}
        }
      }
    }
  }
}
local PRELOADED_PT_FILE_NAME = "sdl_preloaded_pt.json"

local TestData = {
  path = config.pathToSDL .. "TestData",
  isExist = false,
  init = function(self)
    if not self.isExist then
      os.execute("mkdir ".. self.path)
      os.execute("echo 'List test data files files:' > " .. self.path .. "/index.txt")
      self.isExist = true
    end
  end,
  store = function(self, message, pathToFile, fileName)
    if self.isExist then
      local dataToWrite = message

      if pathToFile and fileName then
        os.execute(table.concat({"cp ", pathToFile, " ", self.path, "/", fileName}))
        dataToWrite = table.concat({dataToWrite, " File: ", fileName})
      end

      dataToWrite = dataToWrite .. "\n"
      local file = io.open(self.path .. "/index.txt", "a+")
      file:write(dataToWrite)
      file:close()
    end
  end,
  delete = function(self)
    if self.isExist then
      os.execute("rm -r -f " .. self.path)
      self.isExist = false
    end
  end,
  info = function(self)
    if self.isExist then
      commonFunctions:userPrint(35, "All test data generated by this test were stored to folder: " .. self.path)
    else
      commonFunctions:userPrint(35, "No test data were stored" )
    end
  end
}

--[[ Local Functions ]]
local function constructPathToDatabase()
  if commonSteps:file_exists(config.pathToSDL .. "storage/policy.sqlite") then
    return config.pathToSDL .. "storage/policy.sqlite"
  elseif commonSteps:file_exists(config.pathToSDL .. "policy.sqlite") then
    return config.pathToSDL .. "policy.sqlite"
  else
    commonFunctions:userPrint(31, "policy.sqlite is not found" )
    return nil
  end
end

local function executeSqliteQuery(rawQueryString, dbFilePath)
  if not dbFilePath then
    return nil
  end
  local queryExecutionResult = {}
  local queryString = table.concat({"sqlite3 ", dbFilePath, " '", rawQueryString, "'"})
  local file = io.popen(queryString, 'r')
  if file then
    local index = 1
    for line in file:lines() do
      queryExecutionResult[index] = line
      index = index + 1
    end
    file:close()
    return queryExecutionResult
  else
    return nil
  end
end

local function isValuesCorrect(actualValues, expectedValues)
  if #actualValues ~= #expectedValues then
    return false
  end

  local tmpExpectedValues = {}
  for i = 1, #expectedValues do
    tmpExpectedValues[i] = expectedValues[i]
  end

  local isFound
  for j = 1, #actualValues do
    isFound = false
    for key, value in pairs(tmpExpectedValues) do
      if value == actualValues[j] then
        isFound = true
        tmpExpectedValues[key] = nil
        break
      end
    end
    if not isFound then
      return false
    end
  end
  if next(tmpExpectedValues) then
    return false
  end
  return true
end

function Test.checkLocalPT(checkTable)
  local expectedLocalPtValues
  local queryString
  local actualLocalPtValues
  local comparationResult
  local isTestPass = true
  for _, check in pairs(checkTable) do
    expectedLocalPtValues = check.expectedValues
    queryString = check.query
    actualLocalPtValues = executeSqliteQuery(queryString, constructPathToDatabase())
    if actualLocalPtValues then
      comparationResult = isValuesCorrect(actualLocalPtValues, expectedLocalPtValues)
      if not comparationResult then
        TestData:store(table.concat({"Test ", queryString, " failed: SDL has wrong values in LocalPT"}))
        TestData:store("ExpectedLocalPtValues")
        commonFunctions:userPrint(31, table.concat({"Test ", queryString, " failed: SDL has wrong values in LocalPT"}))
        commonFunctions:userPrint(35, "ExpectedLocalPtValues")
        for _, values in pairs(expectedLocalPtValues) do
          TestData:store(values)
          print(values)
        end
        TestData:store("ActualLocalPtValues")
        commonFunctions:userPrint(35, "ActualLocalPtValues")
        for _, values in pairs(actualLocalPtValues) do
          TestData:store(values)
          print(values)
        end
        isTestPass = false
      end
    else
      TestData:store("Test failed: Can't get data from LocalPT")
      commonFunctions:userPrint(31, "Test failed: Can't get data from LocalPT")
      isTestPass = false
    end
  end
  return isTestPass
end

function Test.backupPreloadedPT(backupPrefix)
  os.execute(table.concat({"cp ", config.pathToSDL, PRELOADED_PT_FILE_NAME, " ", config.pathToSDL, backupPrefix, PRELOADED_PT_FILE_NAME}))
end

function Test.restorePreloadedPT(backupPrefix)
  os.execute(table.concat({"mv ", config.pathToSDL, backupPrefix, PRELOADED_PT_FILE_NAME, " ", config.pathToSDL, PRELOADED_PT_FILE_NAME}))
end

function Test.updatePreloadedPt(updaters)
  local pathToFile = config.pathToSDL .. PRELOADED_PT_FILE_NAME
  local file = io.open(pathToFile, "r")
  local json_data = file:read("*a")
  file:close()

  local data = json.decode(json_data)
  if data then
    for _, updateFunc in pairs(updaters) do
      updateFunc(data)
    end
  end

  local dataToWrite = json.encode(data)
  file = io.open(pathToFile, "w")
  file:write(dataToWrite)
  file:close()
end

function Test:prepareInitialPreloadedPT()
  local initialUpdaters = {
    function(data)
      for key,_ in pairs(data.policy_table.functional_groupings) do
        if key ~= "Base-4" and key ~= "Base-6" and key ~= "BaseBeforeDataConsent" then
          data.policy_table.functional_groupings[key] = nil
        end
      end
    end,
    function(data)
      data.policy_table.module_config.preloaded_date = TESTED_DATA.preloaded_date[1]
    end,
    function(data)
      data.policy_table.app_policies = TESTED_DATA[1].app_policies
    end
  }
  self.updatePreloadedPt(initialUpdaters)
end

function Test:prepareNewPreloadedPT()
  local newUpdaters = {
    function(data)
      data.policy_table.functional_groupings["Location-1"] = TESTED_DATA[2]["Location-1"]
    end,
    function(data)
      data.policy_table.module_config.preloaded_date = TESTED_DATA.preloaded_date[2]
    end,
  }
  self.updatePreloadedPt(newUpdaters)
end

--[[ Preconditions ]]
commonFunctions:newTestCasesGroup("Preconditions")
function Test:Precondition_StopSDL()
  TestData:init()
  StopSDL(self)
end

function Test:Precondition()
  commonSteps:DeletePolicyTable()
  self.backupPreloadedPT("backup_")

  self:prepareInitialPreloadedPT()
  TestData:store("Initial Preloaded PT is stored", config.pathToSDL .. PRELOADED_PT_FILE_NAME, "initial_" .. PRELOADED_PT_FILE_NAME)
end

--[[ Test ]]
commonFunctions:newTestCasesGroup("Test")

function Test:Test_FirstStartSDL()
  StartSDL(config.pathToSDL, true, self)
end

function Test:Test_InitialLocalPT()
  os.execute("sleep 3")
  TestData:store("Initial Local PT is stored", constructPathToDatabase(), "initial_policy.sqlite")
  local checks = {
    {
      query = 'select preloaded_date from module_config',
      expectedValues = {TESTED_DATA.preloaded_date[1]}
    },
    {
      query = 'select name from functional_group',
      expectedValues = {"BaseBeforeDataConsent", "Base-4", "Base-6"}
    }
  }
  if not self.checkLocalPT(checks) then
    self:FailTestCase("SDL has wrong values in LocalPT")
  end
end

function Test:Test_FirstStopSDL()
  StopSDL(self)
end

function Test:Test_NewPreloadedPT()
  self:prepareNewPreloadedPT()
  TestData:store("New Preloaded PT is stored", config.pathToSDL .. PRELOADED_PT_FILE_NAME, "new_" .. PRELOADED_PT_FILE_NAME)
end

function Test:Test_SecondStartSDL()
  StartSDL(config.pathToSDL, true, self)
end

function Test:Test_NewLocalPT()
  os.execute("sleep 3")
  TestData:store("New Local PT is stored", constructPathToDatabase(), "new_policy.sqlite")
  local checks = {
    {
      query = 'select preloaded_date from module_config',
      expectedValues = {TESTED_DATA.preloaded_date[2]}
    },
    {
      query = 'select name from functional_group',
      expectedValues = {"BaseBeforeDataConsent", "Base-4", "Base-6", "Location-1"}
    }
  }
  if not self.checkLocalPT(checks) then
    self:FailTestCase("SDL has wrong values in LocalPT")
  end
end

--[[ Postconditions ]]
commonFunctions:newTestCasesGroup("Postconditions")

function Test:Postcondition()
  commonSteps:DeletePolicyTable()
  self.restorePreloadedPT("backup_")
  StopSDL()
  TestData:info()
end

commonFunctions:SDLForceStop()
return Test
