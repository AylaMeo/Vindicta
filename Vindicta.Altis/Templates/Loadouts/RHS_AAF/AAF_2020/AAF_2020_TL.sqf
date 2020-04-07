removeAllWeapons this;
removeAllItems this;
removeAllAssignedItems this;
removeUniform this;
removeVest this;
removeBackpack this;
removeHeadgear this;
removeGoggles this;

_RandomVest = selectRandom ["FGN_AAF_CIRAS_TL","FGN_AAF_CIRAS_TL_CamB"];
this addVest _RandomVest;
_RandomHeadgear = selectRandom ["FGN_AAF_PASGT","FGN_AAF_PASGT_ESS","FGN_AAF_PASGT_ESS_2","FGN_AAF_PASGT_Type07","FGN_AAF_PASGT_Type07_ESS","FGN_AAF_PASGT_Type07_ESS_2"];
this addHeadgear _RandomHeadgear;
_RandomGoggles = selectRandom ["FGN_AAF_Shemag_tan","FGN_AAF_Shemag","rhs_scarf","","",""];
this addGoggles _RandomGoggles;
this forceAddUniform "FGN_AAF_M10_Type07_Summer";

this addWeapon "rhs_weap_m21a";
this addPrimaryWeaponItem "rhs_acc_2dpZenit";
this addPrimaryWeaponItem "rhs_acc_pkas";
this addPrimaryWeaponItem "rhsgref_30rnd_556x45_m21";
this addWeapon "rhs_weap_tt33";
this addHandgunItem "rhs_mag_762x25_8";
this addWeapon "rhssaf_zrak_rd7j";

this addItemToUniform "FirstAidKit";
this addItemToUniform "FGN_AAF_PatrolCap_Type07";
this addItemToUniform "rhs_acc_perst1ik";
for "_i" from 1 to 2 do {this addItemToUniform "Chemlight_green";};
this addItemToVest "rhs_acc_1pn93_1";
for "_i" from 1 to 4 do {this addItemToVest "rhsgref_30rnd_556x45_m21";};
for "_i" from 1 to 2 do {this addItemToVest "rhs_mag_762x25_8";};
for "_i" from 1 to 2 do {this addItemToVest "rhsgref_30rnd_556x45_m21_t";};
this addItemToVest "rhs_grenade_anm8_mag";
this addItemToVest "rhs_grenade_mki_mag";
for "_i" from 1 to 2 do {this addItemToVest "rhs_grenade_mkii_mag";};
this linkItem "ItemMap";
this linkItem "ItemCompass";
this linkItem "ItemWatch";
this linkItem "ItemRadio";
this linkItem "rhsusf_ANPVS_14";