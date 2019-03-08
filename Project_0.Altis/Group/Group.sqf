#define OOP_INFO
#define OOP_ERROR
#define OOP_WARNING
#define OOP_DEBUG
#define OFSTREAM_FILE "Main.rpt"
#include "Group.hpp"
#include "..\Unit\Unit.hpp"
#include "..\OOP_Light\OOP_Light.h"
#include "..\Mutex\Mutex.hpp"
#include "..\Message\Message.hpp"
#include "..\MessageTypes.hpp"
#include "..\GlobalAssert.hpp"

// Class: Group
/*
Virtualized Group has <Unit> objects inside it.

Unlike standard ARMA group, it can have men, vehicles and drones inside it.

Author: Sparker
11.06.2018
*/

#define pr private

CLASS(GROUP_CLASS_NAME, "MessageReceiverEx");

	//Variables
	VARIABLE("data");

	// |                             N E W                                  |
	/*
	Method: new

	Parameters: _side, _groupType,

	_side - Side (west, east, etc) of this group
	_groupType - Number, group type, see <GROUP_TYPE>

	Returns: nil
	*/
	METHOD("new") {
		params [["_thisObject", "", [""]], ["_side", WEST, [WEST]], ["_groupType", GROUP_TYPE_IDLE, [GROUP_TYPE_IDLE]]];
		
		PROFILER_COUNTER_INC(GROUP_CLASS_NAME);
		
		OOP_INFO_2("side: %1, group type: %2", _side, _groupType);

		// Check existance of neccessary global objects
		ASSERT_GLOBAL_OBJECT(gMessageLoopMain);

		private _data = GROUP_DATA_DEFAULT;
		_data set [GROUP_DATA_ID_SIDE, _side];
		_data set [GROUP_DATA_ID_TYPE, _groupType];
		_data set [GROUP_DATA_ID_MUTEX, MUTEX_NEW()];
		SET_VAR(_thisObject, "data", _data);
	} ENDMETHOD;


	// |                            D E L E T E
	/*
	Method: delete
	*/
	METHOD("delete") {
		params [["_thisObject", "", [""]]];
		
		PROFILER_COUNTER_DEC(GROUP_CLASS_NAME);
		
		OOP_INFO_0("");

		pr _data = T_GETV("data");
		pr _units = _data select GROUP_DATA_ID_UNITS;

		// Delete the group from its garrison
		pr _gar = _data select GROUP_DATA_ID_GARRISON;
		if (_gar != "") then {
			CALLM1(_gar, "removeGroup", _thisObject);
		};

		// Despawn if spawned
		CALLM0(_thisObject, "despawn");

		// Report an error if we are deleting a group with units in it
		if(count _units > 0) then {
			OOP_ERROR_2("Deleting a group that has units in it: %1, %2", _thisObject, _data);
			{
				DELETE(_x);
			} forEach _units;
		};

	} ENDMETHOD;

	/*
	Method: getMessageLoop
	See <MessageReceiver.getMessageLoop>

	Returns: <MessageLoop>
	*/
	// Returns the message loop this object is attached to
	METHOD("getMessageLoop") {
		gMessageLoopMain
	} ENDMETHOD;


	// |                           A D D   U N I T
	/*
	Method: addUnit
	Adds existing <Unit> to this group. Also use it when you want to move unit between groups.

	Parameters: _units

	_unit - <Unit> to add

	Returns: nil
	*/
	METHOD("addUnit") {
		params [["_thisObject", "", [""]], ["_unit", "", [""]]];

		OOP_INFO_1("%1", _unit);

		private _data = GET_VAR(_thisObject, "data");

		pr _unitIsSpawned = CALLM0(_unit, "isSpawned");
		pr _groupIsSpawned = CALLM0(_thisObject, "isSpawned");

		if (_unitIsSpawned && !_groupIsSpawned || !_unitIsSpawned && _groupIsSpawned) exitWith {
			OOP_ERROR_4("Group %1 is spawned: %2, unit %3 is spawned: %3", _thisObject, _groupIsSpawned, _unit, _unitIsSpawned);
		};

		// Get unit's group
		pr _unitGroup = CALLM0(_unit, "getGroup");

		// Remove the unit from its previous group
		if (_unitGroup != "") then {
			//if (CALLM0(_unitGroup, "getOwner") == clientOwner) then {
				CALLM1(_unitGroup, "removeUnit", _unit);
			//} else {
			//	CALLM3(_unitGroup, "postMethodAsync", "removeUnit", [_unit], false);
				//CALLM1(_unitGroup, "waitUntilMessageDone", _msgID);
			//};
		};

		// Add unit to the new group
		private _unitList = _data select GROUP_DATA_ID_UNITS;
		_unitList pushBackUnique _unit;
		CALLM1(_unit, "setGroup", _thisObject);

		// Associate the unit with the garrison of this group
		// todo

		// Handle spawn states
		if (CALLM0(_thisObject,"isSpawned")) then {

			// Make the unit join the actual group
			pr _newGroupHandle = _data select GROUP_DATA_ID_GROUP_HANDLE;

			// Create group handle if it doesn't exist yet
			if (isNull _newGroupHandle) then {
				_newGroupHandle = createGroup [_data select GROUP_DATA_ID_SIDE, false]; //side, delete when empty
				_newGroupHandle allowFleeing 0; // Never flee
				_data set [GROUP_DATA_ID_GROUP_HANDLE, _newGroupHandle];
			};

			pr _unitObjectHandle = CALLM0(_unit, "getObjectHandle");

			[_unitObjectHandle] join _newGroupHandle;

			// If the target group is spawned, notify its AI object
			pr _AI = _data select GROUP_DATA_ID_AI;
			if (_AI != "") then {
				CALLM2(_AI, "postMethodSync", "handleUnitsAdded", [[_unit]]);
			};
		};
	} ENDMETHOD;

	/*
	Method: addGroup
	Moves all units from second group into this group.

	Parameters: _group

	_group - the group to move into this group
	_delete - Boolean, true - deletes the abandoned group. Default: false.

	Returns: nil
	*/

	METHOD("addGroup") {
		params [["_thisObject", "", [""]], ["_group", "", [""]], ["_delete", false]];

		OOP_INFO_1("%1", _group);

		// Get units of the other group
		pr _units = CALLM0(_group, "getUnits");

		// Add all units to this group
		{
			CALLM1(_thisObject, "addUnit", _x);
		} forEach _units;

		// Delete the other group if needed
		if (_delete) then {
			DELETE(_group);
		};
	} ENDMETHOD;

	// ----------------------------------------------------------------------
	// |                        R E M O V E   U N I T                       |
	// ----------------------------------------------------------------------
	/*
	Method: removeUnit
	Removes a unit from this group.

	Access: internal use

	Parameters: _unit, _newGroup

	_unit - <Unit> that will be removed from this group.

	Returns: nil
	*/
	METHOD("removeUnit") {
		params [["_thisObject", "", [""]], ["_unit", "", [""]]];

		OOP_INFO_1("%1", _unit);

		pr _data = GETV(_thisObject, "data");
		pr _units = _data select GROUP_DATA_ID_UNITS;

		// Notify group AI of this unit
		if (CALLM0(_thisObject, "isSpawned")) then {
			pr _AI = _data select GROUP_DATA_ID_AI;
			if (_AI != "") then {
				pr _msgID = CALLM3(_AI, "postMethodAsync", "handleUnitsRemoved", [[_unit]], true);
				CALLM1(_AI, "waitUntilMessageDone", _msgID);
			};
		};

		// Remove the unit from this group
		_units deleteAt (_units find _unit);
		CALLM1(_unit, "setGroup", "");
	} ENDMETHOD;




	// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
	// |                          G E T T I N G   M E M B E R   V A L U E S
	// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -



	// |                         G E T   U N I T S
	/*
	Method: getUnits
	Returns an array with units in this group.

	Returns: Array of units.
	*/
	METHOD("getUnits") {
		params [["_thisObject", "", [""]]];
		private _data = GET_VAR(_thisObject, "data");
		private _unitList = _data select GROUP_DATA_ID_UNITS;
		private _return = +_unitList;
		_return
	} ENDMETHOD;

	// |                         G E T  I N F A N T R Y  U N I T S
	/*
	Method: getInfantryUnits
	Returns all infantry units.

	Returns: Array of units.
	*/
	METHOD("getInfantryUnits") {
		params [["_thisObject", "", [""]]];
		private _data = GET_VAR(_thisObject, "data");
		private _unitList = _data select GROUP_DATA_ID_UNITS;
		_unitList select {CALLM0(_x, "isInfantry")}
	} ENDMETHOD;

	// |                         G E T   V E H I C L E   U N I T S
	/*
	Method: getVehiucleUnits
	Returns all vehicle units.

	Returns: Array of units.
	*/
	METHOD("getVehicleUnits") {
		params [["_thisObject", "", [""]]];
		private _data = GET_VAR(_thisObject, "data");
		private _unitList = _data select GROUP_DATA_ID_UNITS;
		_unitList select {CALLM0(_x, "isVehicle")}
	} ENDMETHOD;

	// |                         G E T   D R O N E   U N I T S
	/*
	Method: getVehicleUnits
	Returns all drone units.

	Returns: Array of units.
	*/
	METHOD("getDroneUnits") {
		params [["_thisObject", "", [""]]];
		private _data = GET_VAR(_thisObject, "data");
		private _unitList = _data select GROUP_DATA_ID_UNITS;
		_unitList select {CALLM0(_x, "isDrone")}
	} ENDMETHOD;


	// |                         G E T   T Y P E                            |
	/*
	Method: getType
	Returns <GROUP_TYPE>

	Returns: Number, group type. See <GROUP_TYPE>,
	*/
	METHOD("getType") {
		params [["_thisObject", "", [""]]];
		private _data = GET_VAR(_thisObject, "data");
		_data select GROUP_DATA_ID_TYPE
	} ENDMETHOD;

	// |                         G E T   S I D E                            |
	/*
	Method: getSide
	Returns side of this group

	Returns: Side
	*/
	METHOD("getSide") {
		params [["_thisObject", "", [""]]];
		private _data = GET_VAR(_thisObject, "data");
		_data select GROUP_DATA_ID_SIDE
	} ENDMETHOD;


	// |                  G E T   G R O U P   H A N D L E
	/*
	Method: getGroupHandle
	Returns the group handle of this group.

	Returns: group handle.
	*/
	METHOD("getGroupHandle") {
		params [["_thisObject", "", [""]]];
		private _data = GET_VAR(_thisObject, "data");
		_data select GROUP_DATA_ID_GROUP_HANDLE
	} ENDMETHOD;

	// |                  G E T   L E A D E R
	/*
	Method: getLeader
	Returns the leader of the group.

	Returns: <Unit> object
	*/
	METHOD("getLeader") {
		params ["_thisObject"];
		pr _data = GET_VAR(_thisObject, "data");
		pr _hG = _data select GROUP_DATA_ID_GROUP_HANDLE;

		pr _hLeader = leader _hG;
		CALLSM1("Unit", "getUnitFromObjectHandle", _hLeader)
	} ENDMETHOD;


	// |                     S E T / G E T   G A R R I S O N                |
	//
	/*
	Method: setGarrison
	Sets the <Garrison> of this garrison.
	Use <Garrison.addGroup> to add a group to a garrison.

	Access: internal use.

	Parameters: _garrison

	_garrison - <Garrison>

	Returns: nil
	*/
	METHOD("setGarrison") {
		params [["_thisObject", "", [""]], ["_garrison", "", [""]] ];
		private _data = GET_VAR(_thisObject, "data");
		_data set [GROUP_DATA_ID_GARRISON, _garrison];

		// Set the garrison of all units in this group
		private _units = _data select GROUP_DATA_ID_UNITS;
		{ CALL_METHOD(_x, "setGarrison", [_garrison]); } forEach _units;
	} ENDMETHOD;


	/*
	Method: getGarrison
	Returns the <Garrison> this Group is attached to.

	Returns: String, <Garrison>
	*/
	METHOD("getGarrison") {
		params [["_thisObject", "", [""]]];
		private _data = GET_VAR(_thisObject, "data");
		_data select GROUP_DATA_ID_GARRISON
	} ENDMETHOD;


	// |                           G E T   A I
	/*
	Method: getAI
	Returns the <AI> of this group, if it's spawned, or "" otherwise.

	Returns: String, <AIGroup>
	*/
	METHOD("getAI") {
		params [["_thisObject", "", [""]]];

		pr _data = GETV(_thisObject, "data");
		_data select GROUP_DATA_ID_AI
	} ENDMETHOD;

	// |                           I S   S P A W N E D
	/*
	Method: isSpawned
	Returns the spawned state of this group

	Returns: Bool
	*/
	METHOD("isSpawned") {
		params [["_thisObject", "", [""]]];

		pr _data = GETV(_thisObject, "data");
		_data select GROUP_DATA_ID_SPAWNED
	} ENDMETHOD;


	// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
	// |                                E V E N T   H A N D L E R S
	// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


	// |                 H A N D L E   U N I T   K I L L E D                |
	/*
	Method: handleUnitRemoved
	Called when the unit has been removed (killed or moved to a different place).

	Must be called inside the group's thread, not inside event handler.

	Returns: nil
	*/
	METHOD("handleUnitRemoved") {
		params [["_thisObject", "", [""]], ["_unit", "", [""]]];

		diag_log format ["[Group::handleUnitRemoved] Info: %1", _unit];

		CALLM1(_thisObject, "removeUnit", _unit);
	} ENDMETHOD;


	// |              H A N D L E   U N I T   D E S P A W N E D             |
	/*
	Method: handleUnitDespawned
	NYI

	Returns: nil
	*/
	METHOD("handleUnitDespawned") {
		params [["_thisObject", "", [""]], ["_unit", "", [""]] ];
	} ENDMETHOD;



	// |                 H A N D L E   U N I T   S P A W N E D              |
	/*
	Method: handleUnitSpawned
	NYI

	Returns: nil
	*/
	METHOD("handleUnitSpawned") {
		params [["_thisObject", "", [""]], "_unit"];
	} ENDMETHOD;






	// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
	// |                          S P A W N I N G   A N D   D E S P A W N I N G
	// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -



	// |                           C R E A T E   A I
	/*
	Method: createAI
	Creates an <AIGroup> for this group.

	Access: internal.

	Returns: nil
	*/
	METHOD("createAI") {
		params [["_thisObject", "", [""]]];

		pr _data = GETV(_thisObject, "data");
		pr _groupUnits = _data select GROUP_DATA_ID_UNITS;

		// Create an AI for this group if it has any units
		//if (count _groupUnits > 0) then {
			pr _AI = NEW("AIGroup", [_thisObject]);
			pr _data = GETV(_thisObject, "data");
			_data set [GROUP_DATA_ID_AI, _AI];
			CALLM(_AI, "start", []); // Kick start it
		//};

	} ENDMETHOD;




	// |         S P A W N
	/*
	Method: spawn
	Spawns all the units in this group.

	Parameters: _loc

	_loc - <Location> where the group will spawn.

	Returns: nil
	*/
	METHOD("spawn") {
		params [["_thisObject", "", [""]], ["_loc", "", [""]]];

		OOP_INFO_0("SPAWN");

		pr _data = GETV(_thisObject, "data");
		if (!(_data select GROUP_DATA_ID_SPAWNED)) then {
			pr _groupUnits = _data select GROUP_DATA_ID_UNITS;
			pr _groupType = _data select GROUP_DATA_ID_TYPE;
			{
				private _unit = _x;
				private _unitData = CALL_METHOD(_unit, "getMainData", []);

				// Create a group handle if we have any infantry and the group handle doesn't exist yet
				private _catID = _unitData select 0;
				if (_catID == T_INF) then {
					pr _groupHandle = _data select GROUP_DATA_ID_GROUP_HANDLE;
					if (isNull _groupHandle) then {
						private _side = _data select GROUP_DATA_ID_SIDE;
						_groupHandle = createGroup [_side, false]; //side, delete when empty
						_data set [GROUP_DATA_ID_GROUP_HANDLE, _groupHandle];
					};
				};
				private _args = _unitData + [_groupType]; // ["_catID", 0, [0]], ["_subcatID", 0, [0]], ["_className", "", [""]], ["_groupType", "", [""]]
				private _posAndDir = CALL_METHOD(_loc, "getSpawnPos", _args);
				CALL_METHOD(_unit, "spawn", _posAndDir);
			} forEach _groupUnits;

			// Set group default behaviour
			pr _groupHandle = _data select GROUP_DATA_ID_GROUP_HANDLE;
			_groupHandle setBehaviour "SAFE";

			// Create an AI for this group
			CALLM0(_thisObject, "createAI");

			// Set the spawned flag to true
			_data set [GROUP_DATA_ID_SPAWNED, true];
		} else {
			OOP_WARNING_0("Already spawned");
		};
	} ENDMETHOD;



	// |         D E S P A W N
	/*
	Method: despawn
	Despawns all units in this group. Also deletes the group handle.

	Returns: nil
	*/
	METHOD("despawn") {
		params [["_thisObject", "", [""]]];

		OOP_INFO_0("DESPAWN");

		pr _data = GETV(_thisObject, "data");
		if ((_data select GROUP_DATA_ID_SPAWNED)) then {
			pr _AI = _data select GROUP_DATA_ID_AI;
			if (_AI != "") then {
				// Switch off their brain
				// We must safely delete the AI object because it might be currently used in its own thread
				pr _msg = MESSAGE_NEW_SHORT(_AI, AI_MESSAGE_DELETE);
				pr _msgID = CALLM2(_AI, "postMessage", _msg, true);
				_data set [GROUP_DATA_ID_AI, ""];
				CALLM(_thisObject, "waitUntilMessageDone", [_msgID]);
			};

			// Despawn everything
			pr _groupUnits = _data select GROUP_DATA_ID_UNITS;
			{
				CALL_METHOD(_x, "despawn", []);
			} forEach _groupUnits;

			// Delete the group handle
			pr _groupHandle = _data select GROUP_DATA_ID_GROUP_HANDLE;
			if (count units _groupHandle > 0) then {
				diag_log format ["[Group] Warning: group is not empty at despawning: %1. Units remaining:", _data];
				{
					diag_log format ["  %1,  alive: %2", _x, alive _x];
				} forEach (units _groupHandle);
				_groupHandle deleteGroupWhenEmpty true;
			} else {
				deleteGroup _groupHandle;
			};
			_data set [GROUP_DATA_ID_GROUP_HANDLE, grpNull];

			// Set the spawned flag to false
			_data set [GROUP_DATA_ID_SPAWNED, false];
		} else {
			OOP_WARNING_0("Already despawned");
		};
	} ENDMETHOD;







	// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
	// |                                         G O A P
	// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -



	//                          G E T   S U B A G E N T S
	/*
	Method: getSubagents
	Returns subagents of this agent.
	For group subagents are its units, since their <AIUnit> is processed synchronosuly with <AIGroup> by default.

	Access: Used by AI class

	Returns: array of units.
	*/
	METHOD("getSubagents") {
		params [["_thisObject", "", [""]]];

		// Get all units
		private _data = GET_VAR(_thisObject, "data");
		private _unitList = _data select GROUP_DATA_ID_UNITS;

		// Return only units which actually have an AI object (soldiers and drones)
		/*
		pr _return = _unitList select {
			CALLM(_x, "isInfantry", [])
		};
		*/
		//_return

		// Return all units since vehicles have an AI object too :p
		_unitList
	} ENDMETHOD;


	//                        G E T   P O S S I B L E   G O A L S
	/*
	Method: getPossibleGoals
	Returns the list of goals this agent evaluates on its own.

	Access: Used by AI class

	Returns: Array with goal class names
	*/
	METHOD("getPossibleGoals") {
		//["GoalGroupRelax"]
		["GoalGroupUnflipVehicles"]
	} ENDMETHOD;


	//                      G E T   P O S S I B L E   A C T I O N S
	/*
	Method: getPossibleActions
	Returns the list of actions this agent can use for planning.

	Access: Used by AI class

	Returns: Array with action class names
	*/
	METHOD("getPossibleActions") {
		[]
	} ENDMETHOD;



	// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
	// |                                O W N E R S H I P   T R A N S F E R
	// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

	/*
	Method: serialize
	See <MessageReceiver.serialize>
	*/
	// Must return a single value which can be deserialized to restore value of an object
	METHOD("serialize") {
		params [["_thisObject", "", [""]]];

		diag_log "[Group:serialize] was called!";

		pr _data = GETV(_thisObject, "data");
		pr _units = _data select GROUP_DATA_ID_UNITS;
		//pr _mutex = _data select GROUP_DATA_ID_MUTEX;
		//MUTEX_LOCK(_mutex);

		// Store data on all units in this group
		pr _unitsSerialized = [];
		private _units = _data select GROUP_DATA_ID_UNITS;
		{
			pr _unitDataArray = GETV(_x, "data");
			_unitsSerialized pushBack [_x, +_unitDataArray];
		} forEach _units;

		// Store data about this group
		// ??

		pr _return = [_unitsSerialized, _data];

		//MUTEX_UNLOCK(_mutex);
		_return
	} ENDMETHOD;

	/*
	Method: deserialize
	See <MessageReceiver.deserialize>
	*/
	// Takes the output of deserialize and restores values of an object
	METHOD("deserialize") {
		params [["_thisObject", "", [""]], "_serialData"];

		diag_log "[Group:deserialize] was called!";

		// Unpack the array
		_serialData params ["_unitsSerialized", "_data"];
		SETV(_thisObject, "data", _data);
		_data set [GROUP_DATA_ID_MUTEX, MUTEX_NEW()];

		// Unpack all the units
		{ // forEach _unitsSerialized
			_x params ["_unitObjNameStr", "_unitDataArray"];
			pr _newUnit = NEW_EXISTING("Unit", _unitObjNameStr);
			SETV(_newUnit, "data", +_unitDataArray);

			// Create a new AI for this unit, if it existed
			pr _unitAI = _unitDataArray select UNIT_DATA_ID_AI;
			diag_log format [" --- Old unit AI: %1", _unitAI];
			if (_unitAI != "") then {
				CALLM0(_newUnit, "createAI");
				diag_log format [" --- Created new unit AI: %1", _unitDataArray select UNIT_DATA_ID_AI];
			};
		} forEach _unitsSerialized;

		// Create a new AI for this group
		if ((_data select GROUP_DATA_ID_AI) != "") then {
			CALLM0(_thisObject, "createAI");
		};

	} ENDMETHOD;

	/*
	Method: transferOwnership
	See <MessageReceiver.transferOwnership>
	*/
	METHOD("transferOwnership") {
		params [ ["_thisObject", "", [""]], ["_newOwner", 0, [0]] ];

		diag_log "[Group:transferOwnership] was called!";

		pr _data = GETV(_thisObject, "data");

		// Delete the AI of this group
		// todo transfer the AI instead, or just transfer the goals and most important data?
		pr _AI = _data select GROUP_DATA_ID_AI;
		if (_AI != "") then {
			pr _msg = MESSAGE_NEW_SHORT(_AI, AI_MESSAGE_DELETE);
			pr _msgID = CALLM2(_AI, "postMessage", _msg, true);
			//if (_msgID < 0) then {diag_log format ["--- Got wrong msg ID %1 %2 %3", _msgID, __FILE__, __LINE__];};
			CALLM(_thisObject, "waitUntilMessageDone", [_msgID]);
		};

		// Delete AI of all the units
		pr _units = _data select GROUP_DATA_ID_UNITS;
		{
			pr _unitData = GETV(_x, "data");
			pr _unitAI = _unitData select UNIT_DATA_ID_AI;
			if (_unitAI != "") then {
				pr _msg = MESSAGE_NEW_SHORT(_unitAI, AI_MESSAGE_DELETE);
				pr _msgID = CALLM2(_unitAI, "postMessage", _msg, true);
				//diag_log format ["--- Got msg ID %1 %2 %3 while deleting Unit's AI", _msgID, __FILE__, __LINE__];
				CALLM(_thisObject, "waitUntilMessageDone", [_msgID]);
			};
		} forEach _units;

		// Switch group owner if the group was spawned
		pr _groupHandle = _data select GROUP_DATA_ID_GROUP_HANDLE;
		if (!isNull _groupHandle) then {
			if (clientOwner == 2) then {
				_groupHandle setGroupOwner _newOwner;
			} else {
				[_groupHandle, _newOwner] remoteExecCall ["setGroupOwner", 2, false];
			};
		};

		// We're done here
		true
	} ENDMETHOD;




	// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
	// |                               O T H E R   M E T H O D S
	// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


	// |         C R E A T E   U N I T S   F R O M   T E M P L A T E
	/*
	Method: createUnitsFromTemplate
	Creates units from template and adds them to this group.

	Parameters: _template, _subcatID

	_template - <Template>
	_subcatID - subcategory of this group template

	Returns: Number, amount of created units.
	*/
	METHOD("createUnitsFromTemplate") {
		params [["_thisObject", "", [""]], ["_template", [], [[]]], ["_subcatID", 0, [0]]];
		private _groupData = [_template, _subcatID, -1] call t_fnc_selectGroup;

		// Create every unit and add it to this group
		{
			private _catID = _x select 0;
			private _subcatID = _x select 1;
			private _classID = _x select 2;
			private _args = [_template, _catID, _subcatID, _classID, _thisObject]; //["_template", [], [[]]], ["_catID", 0, [0]], ["_subcatID", 0, [0]], ["_classID", 0, [0]], ["_group", "", [""]]
			NEW("Unit", _args);
		} forEach _groupData;

		(count _groupData)
	} ENDMETHOD;

	/*
	Method: getRequiredCrew
	Returns amount of needed drivers and turret operators for all vehicles in this group.

	Returns: [_nDrivers, _nTurrets]
	*/

	METHOD("getRequiredCrew") {
		params [["_thisObject", "", [""]]];

		pr _units = T_GETV("data") select GROUP_DATA_ID_UNITS;

		pr _nDrivers = 0;
		pr _nTurrets = 0;

		{
			if (CALLM0(_x, "isVehicle")) then {
				pr _className = CALLM0(_x, "getClassName");
				([_className] call misc_fnc_getFullCrew) params ["_n_driver", "_copilotTurrets", "_stdTurrets"];//, "_psgTurrets", "_n_cargo"];
				_nDrivers = _nDrivers + _n_driver;
				_nTurrets = _nTurrets + (count _copilotTurrets) + (count _stdTurrets);
			};
		} forEach _units;

		OOP_INFO_2("getRequiredCrew: drivers: %1, turrets: %2", _nDrivers, _nTurrets);

		[_nDrivers, _nTurrets]
	} ENDMETHOD;

ENDCLASS;