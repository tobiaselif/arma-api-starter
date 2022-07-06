// *********************************************
// TITLE: CFG_TO_JSON.sqf
// LICENSE : GNU General Public License v3.0
// DESCRIPTION: This script converts the contents of a key cfg config to a JSON array, which can then be copied from the clipboard and used to populate JSON files, databases or anything else that is required.
// AUTHOR: Morgan Davies
// USAGE:
//   1) Alter the _CONFIGS hashmap variable to include the config classes you want to add to the json array. Beware of the 10,000,000 limit on array sizes however. You might need to run the config extraction one at a time. See _exampleCONFIGS below for the currently supported configs.
//   2) Run the script in a debug console on arma 3. It may take a few seconds to complete depending on your system specs.
//   3) You should now have a json array on your clipboard. Don't copy it from the debug console output as it will include extra double quotes to escape the existing ones.
//   4) It is worth mentioning that the last JSON element in the array will include a trailing comma, which may make the array invalid (depending on the parser type). Due to the difficulty in extracting said comma out, I haven't bothered fixing it.
// *********************************************

// ** SUPPORTED CONFIGS HASHMAP, CHANGE _CONFIGS TO TARGET SPECIFIC CONFIGS FROM THIS LIST **
// private _exampleCONFIGS = createHashMapFromArray [
//   ["weapons", "getNumber (_x >> 'scope') isEqualTo 2" configClasses (configFile >> "CfgWeapons")],
//   ["magazines", "getNumber (_x >> 'scope') isEqualTo 2" configClasses (configFile >> "CfgMagazines")],
//   ["vehicles", "getNumber (_x >> 'scope') isEqualTo 2" configClasses (configFile >> "CfgVehicles")],
//   ["glasses", "getNumber (_x >> 'scope') isEqualTo 2" configClasses (configFile >> "CfgGlasses")]
// ];
private _CONFIGS = createHashMapFromArray [
  ["vehicles", "getNumber (_x >> 'scope') isEqualTo 2" configClasses (configFile >> "CfgVehicles")]
];
forceunicode 0;
private _jsonClasses = [];

// Calculates the type and subtype of the config item based off it's rough item return. This can be inaccurate.
getType = { params["_NAME", "_ROUGHTYPE"];
  private _SUBTYPE = _ROUGHTYPE select 1;
  private _TYPEARRAY = [false, _SUBTYPE];
  private _found = false;

  switch (_ROUGHTYPE select 0) do {
    case "Weapon": {
      // Hacky way around making a super long OR conditional
      if (_found == false && ["AssaultRifle", "MachineGun", "Shotgun", "Rifle", "SubmachineGun", "SniperRifle"] find _SUBTYPE != -1) then {
        _TYPEARRAY set [0, "Primaries"];
        _found = true;
      };
      if (_found == false && _SUBTYPE == "Handgun") then {
        _TYPEARRAY set [0, "Secondaries"];
        _found = true;
      };
      if (_found == false && ["Launcher", "MissileLauncher", "RocketLauncher"] find _SUBTYPE != -1) then {
        _TYPEARRAY set [0, "Launchers"];
        _found = true;
      };
      if (_found == false && _SUBTYPE == "Throw") then {
        _TYPEARRAY set [0, "Throwables"];
        _found = true;
      };
    };

    case "Item": {
      if (_found == false && _SUBTYPE == "AccessoryMuzzle") then {
        _TYPEARRAY set [0, "Muzzles"];
        _found = true;
      };
      if (_found == false && _SUBTYPE == "AccessoryPointer") then {
        _TYPEARRAY set [0, "Pointers"];
        _found = true;
      };
      if (_found == false && _SUBTYPE == "AccessorySights") then {
        _TYPEARRAY set [0, "Optics"];
        _found = true;
      };
      if (_found == false && _SUBTYPE == "AccessoryBipod") then {
        _TYPEARRAY set [0, "Bipods"];
        _found = true;
      };
      if (_found == false && ["Binocular", "LaserDesignator"] find _SUBTYPE != -1) then {
        _TYPEARRAY set [0, "Binoculars"];
        _found = true;
      };
      if (_found == false && _SUBTYPE == "Compass") then {
        _TYPEARRAY set [0, "Compasses"];
        _found = true;
      };
      if (_found == false && ["FirstAidKit", "Medikit", "MineDetector", "Toolkit"] find _SUBTYPE != -1) then {
        _TYPEARRAY set [0, "Tools"];
        _found = true;
      };
      if (_found == false && _SUBTYPE == "GPS") then {
        _TYPEARRAY set [0, "GPSs"];
        _found = true;
      };
      if (_found == false && _SUBTYPE == "NVGoggles") then {
        _TYPEARRAY set [0, "Goggles"];
        _found = true;
      };
      if (_found == false && _SUBTYPE == "Radio") then {
        _TYPEARRAY set [0, "Radios"];
        _found = true;
      };
      if (_found == false && _SUBTYPE == "UAVTerminal") then {
        _TYPEARRAY set [0, "Terminals"];
        _found = true;
      };
      if (_found == false && _SUBTYPE == "Watch") then {
        _TYPEARRAY set [0, "Watches"];
        _found = true;
      };
    };

    case "Equipment": {
      if (_found == false && _SUBTYPE == "Glasses") then {
        _TYPEARRAY set [0, "Facewear"];
        _found = true;
      };
      if (_found == false && _SUBTYPE == "Headgear") then {
        _TYPEARRAY set [0, "Headgear"];
        _found = true;
      };
      if (_found == false && _SUBTYPE == "Vest") then {
        _TYPEARRAY set [0, "Vests"];
        _found = true;
      };
      if (_found == false && _SUBTYPE == "Uniform") then {
        _TYPEARRAY set [0, "Uniforms"];
        _found = true;
      };
      if (_found == false && _SUBTYPE == "Backpack") then {
        _TYPEARRAY set [0, "Backpacks"];
        _found = true;
      };
      if (_found == false) then {
        // The above SHOULD be the only valid types
        throw format ["[ERROR] Unknown equipment subtype: %1 for config: %2", _SUBTYPE, _NAME];
      };
    };

    case "Magazine": {
      // These SHOULD be the only non-arsenal types
      if (["Artillery", "CounterMeasures", "UnknownMagazine"] find _SUBTYPE == -1) then {
        _TYPEARRAY set [0, "Magazines"];
      };
    };

    case "Mine": {
      if (["Mine", "MineBounding", "MineDirectional"] find _SUBTYPE != -1) then {
        _TYPEARRAY set [0, "Explosives"];
      } else {
        // The above SHOULD be the only valid types
        throw format ["[ERROR] Unknown mine subtype: %1 for config: %2", _SUBTYPE, _NAME];
      };
    };

    default {
      if (_ROUGHTYPE select 0 != "VehicleWeapon" || [_ROUGHTYPE select 0, "/^ +$/"] call regexMatch != true) then {
        // No matching type was found and it isn't an excluded one
        throw format ["[ERROR] Unknown type: %1 for config: %2", _ROUGHTYPE select 0, _NAME];
      };
    };
  };

  _TYPEARRAY
};

// Calculates the mod of the config item based off the author
getModName = { params["_NAME", "_DLC", "_AUTHOR"];
  private _modName = "";

  // I would prefer to use an else if here but it doesn't exist in sqf seemingly
  private _found = false;
  if ((["ACE", _AUTHOR] call BIS_fnc_inString || ["ACE_", _NAME] call BIS_fnc_inString) && _found == false) then {
    _modName = "ace";
    _found = true;
  };
  if ((["3 Commando Brigade", _AUTHOR] call BIS_fnc_inString || ["3commandobrigade", _AUTHOR] call BIS_fnc_inString || ["3CB_", _NAME] call BIS_fnc_inString) && _found == false) then {
    _modName = "3cb";
    _found = true;
  };
  if ((["Red Hammer Studios", _AUTHOR] call BIS_fnc_inString || ["BWMod", _AUTHOR] call BIS_fnc_inString || ["rhs_", _NAME] call BIS_fnc_inString || ["rhsgref_", _NAME] call BIS_fnc_inString || ["RHS_", _DLC] call BIS_fnc_inString) && _found == false) then {
    _modName = "rhs";
    _found = true;
  };
  if ((["Toadie", _AUTHOR] call BIS_fnc_inString || ["Sorry", _AUTHOR] call BIS_fnc_inString || ["Nix", _AUTHOR] call BIS_fnc_inString || ["HLC_Bipod_G36", _NAME] call BIS_fnc_inString) && _found == false) then {
    _modName = "niarms";
    _found = true;
  };
  if (["Ampersand", _AUTHOR] call BIS_fnc_inString && _found == false) then {
    _modName = "breachingcharge";
    _found = true;
  };
  if (["Slatts", _AUTHOR] call BIS_fnc_inString && _found == false) then {
    _modName = "facexscars";
    _found = true;
  };
    if (["G4rrus", _AUTHOR] call BIS_fnc_inString && _found == false) then {
    _modName = "customflashlights";
    _found = true;
  };
  if ((["teriyaki", _AUTHOR] call BIS_fnc_inString || ["Dragonkeeper", _AUTHOR] call BIS_fnc_inString || ["TRYK_", _NAME] call BIS_fnc_inString) && _found == false) then {
    _modName = "tryk";
    _found = true;
  };
  if ((["zabb", _AUTHOR] call BIS_fnc_inString || ["Xmosmos", _AUTHOR] call BIS_fnc_inString || ["TAC_", _NAME] call BIS_fnc_inString) && _found == false) then {
    _modName = "tacvests";
    _found = true;
  };
  if ((["VanSchmoozin", _AUTHOR] call BIS_fnc_inString || ["Bacon", _AUTHOR] call BIS_fnc_inString || ["Alpine_", _NAME] call BIS_fnc_inString || ["DTS_", _NAME] call BIS_fnc_inString || ["_Massif", _NAME] call BIS_fnc_inString || ["_opscore", _NAME] call BIS_fnc_inString || ["VSM_", _NAME] call BIS_fnc_inString) && _found == false) then {
    _modName = "vsm";
    _found = true;
  };
  if (["da12thMonkey", _AUTHOR] call BIS_fnc_inString && _found == false) then {
    _modName = "rksl";
    _found = true;
  };
  if ((["ACRE2Team", _AUTHOR] call BIS_fnc_inString || ["ACRE_", _NAME] call BIS_fnc_inString) && _found == false) then {
    _modName = "acre";
    _found = true;
  };
    if (["Jaffa", _AUTHOR] call BIS_fnc_inString && _found == false) then {
    _modName = "nutresource";
    _found = true;
  };
  if ((["Frisia", _AUTHOR] call BIS_fnc_inString || ["Free World Armoury", _AUTHOR] call BIS_fnc_inString) && _found == false) then {
    _modName = "nutresource3party";
    _found = true;
  };
  if (["Project OPFOR", _AUTHOR] call BIS_fnc_inString && _found == false) then {
    _modName = "projectopfor";
    _found = true;
  };
  if (["Rebel", _AUTHOR] call BIS_fnc_inString && _found == false) then {
    _modName = "immersioncigs";
    _found = true;
  };
  if ((["Enoch", _DLC] call BIS_fnc_inString || ["Contact", _DLC] call BIS_fnc_inString) && _found == false) {
    _modName = "contact";
    _found = true;
  };
  if (["Kart", _DLC] call BIS_fnc_inString && _found == false) {
    _modName = "karts";
    _found = true;
  };
  if (["Mark", _DLC] call BIS_fnc_inString && _found == false) {
    _modName = "marksman";
    _found = true;
  };
  if (["Tank", _DLC] call BIS_fnc_inString && _found == false) {
    _modName = "tanks";
    _found = true;
  };
  if (["Expansion", _DLC] call BIS_fnc_inString && _found == false) {
    _modName = "apex";
    _found = true;
  };
  if (["AoW", _DLC] call BIS_fnc_inString && _found == false) {
    _modName = "artofwar";
    _found = true;
  };
  if (["Heli", _DLC] call BIS_fnc_inString && _found == false) {
    _modName = "helicopters";
    _found = true;
  };
  if (["Orange", _DLC] call BIS_fnc_inString && _found == false) {
    _modName = "lawsofwar";
    _found = true;
  };
  if ((["Bravo Zero One Studios", _AUTHOR] call BIS_fnc_inString || ["Jets", _DLC] call BIS_fnc_inString) && _found == false) {
    _modname = "jets";
    _found = true;
  }
  if ((["Bohemia Interactive", _AUTHOR] call BIS_fnc_inString || _NAME == "None") && _found == false) then {
    _modName = "vanilla";
    _found = true;
  };

  // Not found, either object is a placeholder null class, author is not provided or is not supported yet
  if (_found == false) then {
    throw format ["[ERROR] Unknown mod author for class = %1", _NAME];
  };

  _modName
};

// START: Iterate over config files
{
  private _CONFIGTYPE = _x;
  private _CONFIGARRAY = _y apply {
    private _CONFIGNAME = configName _x;
    private _DLCNAME = getText (_x >> "dlc");
    private _TYPE = [_CONFIGNAME, _CONFIGNAME call BIS_fnc_itemType] call getType;
    // Hacky way around checking if a variable is false
    if (typeName (_TYPE select 0) == "BOOL") then {
      continue;
    };

    // Format each hit to a JSON object and strip out chars that interfere with JSON parsing
    switch (_CONFIGTYPE) do {
      case "weapons": {
        format [
          '  {%1    "class":"%2",%3    "name":"%4",%5    "description":"%6",%7    "image":"%8",%9    "magazines":%10,%11    "type":"%12",%13    "subtype":"%14",%15    "mod":"%16",%17    "weight":%18,%19    "magwell":%20%21  },%22',
          endl,
          _CONFIGNAME,
          endl,
          [[getText (_x >> "displayName"), "\", ""] call CBA_fnc_replace, '"', '\"'] call CBA_fnc_replace,
          endl,
          [[getText (_x >> "descriptionShort"),  "\", ""] call CBA_fnc_replace, '"', '\"'] call CBA_fnc_replace,
          endl,
          [getText (_x >> "Picture"), "\", "\\"] call CBA_fnc_replace,
          endl,
          getArray (_x >> "magazines") apply {_x}, // Note: _x is block specific
          endl,
          _TYPE select 0,
          endl,
          _TYPE select 1,
          endl,
          [_CONFIGNAME, _DLCNAME, getText (_x >> "author")] call getModName,
          endl,
          getNumber (_x >> "mass"),
          endl,
          getArray (_x >> "magazineWell") apply {_x},
          endl,
          endl
        ]
      };

      case "magazines": {
        format [
          '  {%1    "class":"%2",%3    "name":"%4",%5    "description":"%6",%7    "image":"%8",%9    "ammo":"%10",%11    "count":%12,%13    "mod":"%14",%15    "weight":%16,%17    "type":"%18",%19    "subtype":"%20"%21  },%22',
          endl,
          _CONFIGNAME,
          endl,
          [[getText (_x >> "displayName"), "\", ""] call CBA_fnc_replace, '"', '\"'] call CBA_fnc_replace,
          endl,
          [[getText (_x >> "descriptionShort"),  "\", ""] call CBA_fnc_replace, '"', '\"'] call CBA_fnc_replace,
          endl,
          [getText (_x >> "picture"), "\", "\\"] call CBA_fnc_replace,
          endl,
          [[getText (_x >> "ammo"), "\", ""] call CBA_fnc_replace, '"', '\"'] call CBA_fnc_replace,
          endl,
          getNumber (_x >> "count"),
          endl,
          [_CONFIGNAME, _DLCNAME, getText (_x >> "author")] call getModName,
          endl,
          getNumber (_x >> "mass"),
          endl,
          _TYPE select 0,
          endl,
          _TYPE select 1,
          endl,
          endl
        ]
      };

      case "vehicles": {
        format [
          '  {%1    "class":"%2",%3    "name":"%4",%5    "description":"%6",%7    "image":"%8",%9    "mod":"%10",%11    "weight":%12,%13    "type":"%14",%15    "subtype":"%16"%17  },%18',
          endl,
          _CONFIGNAME,
          endl,
          [[getText (_x >> "displayName"), "\", ""] call CBA_fnc_replace, '"', '\"'] call CBA_fnc_replace,
          endl,
          [[getText (_x >> "descriptionShort"),  "\", ""] call CBA_fnc_replace, '"', '\"'] call CBA_fnc_replace,
          endl,
          [getText (_x >> "picture"), "\", "\\"] call CBA_fnc_replace,
          endl,
          [_CONFIGNAME, _DLCNAME, getText (_x >> "author")] call getModName,
          endl,
          getNumber (_x >> "mass"),
          endl,
          _TYPE select 0,
          endl,
          _TYPE select 1,
          endl,
          endl
        ]
      };

      case "glasses": {
        format [
          '  {%1    "class":"%2",%3    "name":"%4",%5    "description":"%6",%7    "image":"%8",%9    "mod":"%10",%11    "weight":%12,%13    "type":"%14",%15    "subtype":"%16"%17  },%18',
          endl,
          _CONFIGNAME,
          endl,
          [[getText (_x >> "displayName"), "\", ""] call CBA_fnc_replace, '"', '\"'] call CBA_fnc_replace,
          endl,
          [[getText (_x >> "descriptionShort"),  "\", ""] call CBA_fnc_replace, '"', '\"'] call CBA_fnc_replace,
          endl,
          [getText (_x >> "picture"), "\", "\\"] call CBA_fnc_replace,
          endl,
          [_CONFIGNAME, _DLCNAME, getText (_x >> "author")] call getModName,
          endl,
          getNumber (_x >> "mass"),
          endl,
          _TYPE select 0,
          endl,
          _TYPE select 1,
          endl,
          endl
        ]
      };

      default {
        throw format ["[ERROR] Unsupported config title: %1 please specify a supported title", _CONFIGTYPE];
      };
    };
  };

  // Concatenate all collected objects and add to json array
  _jsonClasses append _CONFIGARRAY;

} forEach _CONFIGS;

// Remove random null classes, we have to do it more than once as CBA_fnc_replace has a limit of around 10000 lines
private _joinedClasses = [_jsonClasses joinString endl, "<null>", ""] call CBA_fnc_replace;
while {["<null>", _joinedClasses] call BIS_fnc_inString} do {
  _filteredClasses = [_joinedClasses, "<null>", ""] call CBA_fnc_replace;
  _joinedClasses = _filteredClasses;
};

// Convert to json array and finish
_JSON = "[" + endl + "  " + _joinedClasses + endl + "]" + endl;
copyToClipboard _JSON;
_JSON
