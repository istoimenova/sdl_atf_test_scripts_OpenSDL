---------------------------------------------------------------------------------------------
-- TODO(istoimenova): Update when "[GENIVI] Local Policy Table DB is not created according to data dictionary" is fixed
-- Requirement summary:
-- [Policies] Merging rules for "usage_and_error_count" section
--
-- Description:
-- Check of merging rules for "usage_and_error_count" section
-- 1. Used preconditions
-- Delete files and policy table from previous ignition cycle if any
-- Start SDL with PreloadedPT json file with "preloaded_date" parameter
-- Change data in "usage_and_error_count" section in LocalPT
-- 2. Performed steps
-- Stop SDL
-- Start SDL with corrected PreloadedPT json file with "preloaded_date" parameter with bigger value
--
-- Expected result:
-- SDL must leave all fields & their values of "usage_and_error_count" section as it was in the database without changes
---------------------------------------------------------------------------------------------

--[[ General configuration parameters ]]
config.deviceMAC = "12ca17b49af2289436f303e0166030a21e525d266e209267433801a8fd4071a0"

--[[ Required Shared libraries ]]
local commonFunctions = require ('user_modules/shared_testcases/commonFunctions')
local commonSteps = require ('user_modules/shared_testcases/commonSteps')
local testCasesForPolicyTable = require ('user_modules/shared_testcases/testCasesForPolicyTable')

--[[ Local Variables ]]
local TESTED_DATA = {
  preloaded_date = {"1988-12-01","2015-05-02"},
  usage_and_error_count = {
      count_of_iap_buffer_full = "0",
      count_sync_out_of_memory = "0",
      count_of_sync_reboots = "0"
    },
  app_level = {
      app_registration_language_gui = "FR-FR",
      app_registration_language_vui = "ES-ES",
      count_of_rejected_rpcs_calls = "0",
      count_of_rejections_duplicate_name = "0",
      count_of_rejections_nickname_mismatch = "0"
  }
}

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

--[[ General Precondition before ATF start ]]
config.defaultProtocolVersion = 2
--app_registration_language_gui
config.application1.registerAppInterfaceParams.hmiDisplayLanguageDesired = "FR-FR"
--app_registration_language_vui
config.application1.registerAppInterfaceParams.languageDesired = "ES-ES"
testCasesForPolicyTable.Delete_Policy_table_snapshot()
commonSteps:DeleteLogsFileAndPolicyTable()

--[[ General configuration parameters ]]
--Test = require('user_modules/connecttest_ConnectMobile')
Test = require('connecttest')
require('cardinalities')
require('user_modules/AppTypes')


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

--[[ Test ]]
commonFunctions:newTestCasesGroup("Test")

function Test:TestStep_VerifyInitialLocalPT()
  os.execute("sleep 3")

  local checks = {
    { query = 'select count_of_iap_buffer_full from usage_and_error_count', expectedValues = {TESTED_DATA.usage_and_error_count.count_of_iap_buffer_full}},
    { query = 'select count_sync_out_of_memory from usage_and_error_count', expectedValues = {TESTED_DATA.usage_and_error_count.count_sync_out_of_memory}},
    { query = 'select count_of_sync_reboots from usage_and_error_count', expectedValues = {TESTED_DATA.usage_and_error_count.count_of_sync_reboots} },
    { query = 'select app_registration_language_gui from app_level', expectedValues = {TESTED_DATA.app_level.app_registration_language_gui} },
    { query = 'select app_registration_language_vui from app_level', expectedValues = {TESTED_DATA.app_level.app_registration_language_vui} },
    { query = 'select count_of_rejected_rpcs_calls from app_level', expectedValues = {TESTED_DATA.app_level.count_of_rejected_rpcs_calls} },
    { query = 'select count_of_rejections_duplicate_name from app_level', expectedValues = {TESTED_DATA.app_level.count_of_rejections_duplicate_name} },
    { query = 'select count_of_rejections_nickname_mismatch from app_level', expectedValues = {TESTED_DATA.app_level.count_of_rejections_nickname_mismatch} },
    { query = 'select application_id from app_level', expectedValues = {} }
  }

  if not self.checkLocalPT(checks) then
    self:FailTestCase("SDL has wrong values in LocalPT")
  end
end

function Test:TestStep_trigger_getting_device_consent()
  testCasesForPolicyTable:trigger_getting_device_consent(self, config.application1.registerAppInterfaceParams.appName, config.deviceMAC)
end

function Test:TestStep_flow_SUCCEESS_EXTERNAL_PROPRIETARY()
  testCasesForPolicyTable:flow_SUCCEESS_EXTERNAL_PROPRIETARY(self)
end

function Test:TestStep_VerifyLocalPT_PTU()
  os.execute("sleep 3")

  local checks = {
    { query = 'select count_of_iap_buffer_full from usage_and_error_count', expectedValues = {TESTED_DATA.usage_and_error_count.count_of_iap_buffer_full}},
    { query = 'select count_sync_out_of_memory from usage_and_error_count', expectedValues = {TESTED_DATA.usage_and_error_count.count_sync_out_of_memory}},
    { query = 'select count_of_sync_reboots from usage_and_error_count', expectedValues = {TESTED_DATA.usage_and_error_count.count_of_sync_reboots} },
    { query = 'select app_registration_language_gui from app_level', expectedValues = {TESTED_DATA.app_level.app_registration_language_gui} },
    { query = 'select app_registration_language_vui from app_level', expectedValues = {TESTED_DATA.app_level.app_registration_language_vui} },
    { query = 'select count_of_rejected_rpcs_calls from app_level', expectedValues = {TESTED_DATA.app_level.count_of_rejected_rpcs_calls} },
    { query = 'select count_of_rejections_duplicate_name from app_level', expectedValues = {TESTED_DATA.app_level.count_of_rejections_duplicate_name} },
    { query = 'select count_of_rejections_nickname_mismatch from app_level', expectedValues = {TESTED_DATA.app_level.count_of_rejections_nickname_mismatch} },
    { query = 'select application_id from app_level', expectedValues = {} }
  }

  if not self.checkLocalPT(checks) then
    self:FailTestCase("SDL has wrong values in LocalPT")
  end
end

--[[ Postconditions ]]
commonFunctions:newTestCasesGroup("Postconditions")
function Test.Postcondition_StopSDL()
  StopSDL()
end

return Test
