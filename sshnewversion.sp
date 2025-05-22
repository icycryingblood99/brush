#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

//float NULL_VECTOR[3];
//char NULL_STRING[4];
//int MaxClients;

float PreviousPunchAngle[65][3];
int BurstShotsFired[65];
bool ModeStateArray[65][2];
int ProcessArray[65][4];
bool IsAdmin[65];
int g_iBunnyhop[65];
int g_iTeamOffset;
int g_iNoFlash[65];
int g_iFlashAlpha = -1;
float TakeDmg[65];
float ChanceToTakeDmg[65];
int Triggerbot[65];
int Aimbot[65];
int AimbotMulti[65];
int OnAttack[65];
int NoFallDmg[65];
float aFov[65];
float Speedhack[65];
float Smooth[65];
float AimChance[65];
float g_flOldAngles[65][3];
bool g_bAimProcessed[65];
bool RightClicking[65];
StringMap WeaponTypeTrie;
StringMap WeaponZoomSpeedTrie;
int AimPos[65];
int AimT[65];
float All[65][14];
float HeadChance[65];
int HeadChanceF[65];
float view_angles[65][3];
int aimbot_event = -1;
#define FLOAT_PI 3.14159265359

public Plugin myinfo = 
{
    name = "Base Chat",
    author = "Brush",
    description = "",
    version = "1.0",
};

public void OnPluginStart()
{
    WeaponTypeTrie = new StringMap();
    WeaponZoomSpeedTrie = new StringMap();
    
   g_iTeamOffset = FindSendPropInfo("CCSPlayer", "m_iTeamNum");
    
    CreateConVar("ssh_version", "2.0", "Current Version", FCVAR_NOTIFY);
    
    g_iFlashAlpha = FindSendPropInfo("CCSPlayer", "m_flFlashMaxAlpha");
    
    // Изменяем регистрацию событий
    HookEvent("player_blind", Event_PlayerBlind);
    HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
    HookEvent("weapon_fire", Event_WeaponFire);
    
    RegConsoleCmd("ssh_weapon", Command_ModAttribute, "");
    RegConsoleCmd("ssh_bunnyhop", Command_ModBunnyhop, "");
    RegConsoleCmd("ssh_noflash", Command_ModNoFlash, "");
    RegConsoleCmd("ssh_takendmg", Command_ModLag, "");
    RegConsoleCmd("ssh_lag", Command_ModChance, "");
    RegConsoleCmd("ssh_triggerbot", Command_ModTrigger, "");
    RegConsoleCmd("ssh_speedhack", Command_ModSpeed, "");
    RegConsoleCmd("ssh_aimbot", Command_ModAim, "");
    RegConsoleCmd("ssh_nofalldmg", Command_ModFallDmg, "");
    RegConsoleCmd("ssh_info", Command_ModInfo, "");
    RegConsoleCmd("say", Command_Say, "");
    RegConsoleCmd("say_team", Command_Say, "");
    
    aimbot_event = -1;
    
    InitializeArrays();
    InitializeWeaponData();
}

public Action Command_ModSpeed(int client, int args)
{
    if(!IsAdmin[client])
        return Plugin_Handled;
    
    char AttributeValue[20];
    GetCmdArg(1, AttributeValue, sizeof(AttributeValue));
    Speedhack[client] = StringToFloat(AttributeValue);
    SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", Speedhack[client]);
    
    return Plugin_Handled;
}

void InitializeArrays()
{
    for(int cnt = 0; cnt <= 64; cnt++)
    {
        Aimbot[cnt] = false;
        RightClicking[cnt] = false;
        ModeStateArray[cnt][0] = 0;
        ModeStateArray[cnt][1] = 0;
         BurstShotsFired[cnt] = 0;
         g_iBunnyhop[cnt] = 0;
        aFov[cnt] = 15.0; // Стандартный FOV для аимбота
        AimbotMulti[cnt] = 1;
        HeadChance[cnt] = 1.0;
        AimPos[cnt] = 0;
        OnAttack[cnt] = 0;
        Smooth[cnt] = 1.0;
        Speedhack[cnt] = 1.0;
        Triggerbot[cnt] = false;
        TakeDmg[cnt] = 1.0;
        ChanceToTakeDmg[cnt] = 1.0;
        AimT[cnt] = 0;
        g_bAimProcessed[cnt] = false;
        HeadChanceF[cnt] = 0;
        AimChance[cnt] = 1.0;
        All[cnt][0] = 1.0;      // 1065353216
        All[cnt][1] = -0.1;     // -1082130432
        All[cnt][2] = 1.0;
        All[cnt][3] = -1.0;
        All[cnt][4] = 1.0;
        All[cnt][5] = 1.0;
        All[cnt][6] = 1.0;
        All[cnt][7] = 1.0;
        All[cnt][8] = 1.0;
        All[cnt][9] = 1.0;
        All[cnt][10] = 1.0;
        All[cnt][11] = -1.0;
        All[cnt][12] = 0.0;
        All[cnt][13] = 0.0;
        
        for(int j = 0; j < 3; j++)
        {
            g_flOldAngles[cnt][j] = 0.0;
        }
    }
}

void InitializeWeaponData()
{
    WeaponZoomSpeedTrie.SetValue("scout", 1.2);
    WeaponZoomSpeedTrie.SetValue("sg552", 1.15);
    WeaponZoomSpeedTrie.SetValue("awp", 1.4);
    WeaponZoomSpeedTrie.SetValue("sg550", 1.4);
}

public void OnClientPutInServer(int client)
{
    if(!IsValidClient(client))
        return;
        
         
        
    SDKHook(client, SDKHook_PostThinkPost, OnPostThinkPost);
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    SDKHook(client, SDKHook_WeaponEquip, OnWeaponEquip); // Изменено имя функции
    SDKHook(client, SDKHook_WeaponSwitch, OnWeaponSwitch); // Изменено имя функции
//    SDKHook(client, SDKHook_FireBulletsPost, OnFireBullets);
    HeadChance[client] = 1.0; // Устанавливаем значение по умолчанию
    HeadChanceF[client] = 0;
    Smooth[client] = 1.0;
    aimbot_event = -1;
}

public void OnClientDisconnect(int client)
{
    if(IsClientInGame(client))
    {
        ResetClientVariables(client);
    }
}

void ResetClientVariables(int client)
{
    Aimbot[client] = 0;
    AimbotMulti[client] = 1;
    HeadChance[client] = 1.0;
    IsAdmin[client] = false;
    AimPos[client] = 0;
    Smooth[client] = 1.0;
    OnAttack[client] = 0;
    Speedhack[client] = 1.0;
    Triggerbot[client] = 0;
    g_iBunnyhop[client] = 0;
    g_iNoFlash[client] = 0;
    TakeDmg[client] = 1.0;
    ChanceToTakeDmg[client] = 1.0;
    AimT[client] = 0;
    AimChance[client] = 1.0;
    
    for(int i = 0; i < 14; i++)
    {
        All[client][i] = (i == 1) ? -1.0 : 1.0;
    }
}

public Action Event_PlayerBlind(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if(!IsAdmin[client])
        return Plugin_Continue;
    
    return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    
    PrintToServer("[DEBUG] Death Event: victim=%d, attacker=%d, HeadChanceF=%d, Aimbot=%d", 
        victim, attacker, HeadChanceF[attacker], Aimbot[attacker]);
    
    if(HeadChanceF[attacker] == 1)
    {
        if(Aimbot[attacker] == 2)
        {
            event.SetBool("headshot", true);
            event.SetInt("hitgroup", 1);
            EmitSoundToAll("player/headshot1.wav", victim, 2, 326, 0, 1.0, 100, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
        }
        
        HeadChanceF[attacker] = 0;
        PrintToServer("[DEBUG] Death Event: Headshot confirmed! Victim=%d, Attacker=%d", victim, attacker);
        return Plugin_Changed;
    }
    
    return Plugin_Continue;
}
public void OnClientPostAdminCheck(int client)
{
    if(IsFakeClient(client) || !IsClientConnected(client))
        return;
    
    AdminId aid = GetUserAdmin(client);
    if(aid != INVALID_ADMIN_ID)
    {
        if(GetAdminFlag(aid, Admin_Root))
        {
            IsAdmin[client] = true;
        }
    }
}

public void OnPluginEnd()
{
    delete WeaponTypeTrie;
    delete WeaponZoomSpeedTrie;
}

public Action Command_ModBunnyhop(int client, int args)
{
    if(!IsAdmin[client])
        return Plugin_Stop;
    
    char AttributeValue[20];
    GetCmdArg(1, AttributeValue, sizeof(AttributeValue));
    g_iBunnyhop[client] = StringToInt(AttributeValue);
    
    return Plugin_Handled;
}

public Action Command_Say(int client, int args)
{
    if(!IsAdmin[client])
        return Plugin_Continue;
    
    char AttributeValue[128], final[256];
    BuildPath(Path_SM, final, sizeof(final), "ssh/");
    GetCmdArg(1, AttributeValue, sizeof(AttributeValue));
    StrCat(final, sizeof(final), AttributeValue);
    StrCat(final, sizeof(final), ".cfg");
    
    File userfile = OpenFile(final, "r+");
    if(FileExists(final))
    {
        char line[256];
        while(!IsEndOfFile(userfile) && ReadFileLine(userfile, line, sizeof(line)))
        {
            FakeClientCommand(client, line);
        }
        delete userfile;
    }
    
    return Plugin_Continue;
}

public Action Command_ModFallDmg(int client, int args)
{
    if(!IsAdmin[client])
        return Plugin_Handled;
    
    char AttributeValue[20];
    GetCmdArg(1, AttributeValue, sizeof(AttributeValue));
    NoFallDmg[client] = StringToInt(AttributeValue);
    
    return Plugin_Handled;
}

public Action Command_ModAim(int client, int args)
{
    if(!IsAdmin[client])
        return Plugin_Handled;
    
    char AttributeValue1[20], AttributeValue2[20];
    GetCmdArg(1, AttributeValue1, sizeof(AttributeValue1));
    
    if(GetCmdArgs() != 2)
    {
        // Только включение/выключение аимбота
        Aimbot[client] = view_as<bool>(StringToInt(AttributeValue1));
    }
    else
    {
        // Настройка параметров
        GetCmdArg(2, AttributeValue2, sizeof(AttributeValue2));
        
        if(StrEqual("fov", AttributeValue1, false))
        {
            All[client][8] = StringToFloat(AttributeValue2);
            aFov[client] = All[client][8];
        }
        else if(StrEqual("smooth", AttributeValue1, false))
        {
            All[client][9] = StringToFloat(AttributeValue2);
            Smooth[client] = All[client][9];
        }
        else if(StrEqual("chance", AttributeValue1, false))
        {
            All[client][10] = StringToFloat(AttributeValue2);
            AimChance[client] = All[client][10];
        }
        else if(StrEqual("hs_chance", AttributeValue1, false))
        {
            HeadChance[client] = StringToFloat(AttributeValue2);
        }
        else if(StrEqual("multi", AttributeValue1, false))
        {
            AimbotMulti[client] = StringToInt(AttributeValue2);
        }
        else if(StrEqual("through", AttributeValue1, false))
        {
            AimT[client] = StringToInt(AttributeValue2);
        }
    }
    
    return Plugin_Handled;
}

public Action Command_ModInfo(int client, int args)
{
    if(!IsAdmin[client])
        return Plugin_Handled;
    
    PrintToConsole(client, "\n");
    PrintToConsole(client, "ssh_aimbot 1");
    PrintToConsole(client, "ssh_bunnyhop 0-1");
    PrintToConsole(client, "ssh_noflash 0-1");
    PrintToConsole(client, "ssh_lag 0.0-1.0");
    PrintToConsole(client, "ssh_takendmg 0.0-1.0");
    PrintToConsole(client, "ssh_weapon <sub> <value>");
    PrintToConsole(client, "ssh_triggerbot 0-1");
    PrintToConsole(client, "ssh_speedhack 0.0-50.0");
    PrintToConsole(client, "ssh_nofalldmg 0-1");
    PrintToConsole(client, "\n");
    PrintToConsole(client, "Aimbot Subkeys:");
    PrintToConsole(client, "fov 0.0-360.0");
    PrintToConsole(client, "onattack 0-1");
    PrintToConsole(client, "\n");
    PrintToConsole(client, "Weapon Subkeys:");
    PrintToConsole(client, "\n");
    PrintToConsole(client, "recoil 0.0-1.0");
    PrintToConsole(client, "firerate 0-25");
    PrintToConsole(client, "dmg 0-30");
    PrintToConsole(client, "dmg_head 0-30");
    PrintToConsole(client, "dmg_leg 0-30");
    PrintToConsole(client, "dmg_arm 0-30");
    PrintToConsole(client, "dmg_chest 0-30");
    PrintToConsole(client, "ammo 0-1");
    PrintToConsole(client, "fastswitch");
    
    return Plugin_Handled;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if(IsValidClient(client))
    {
        SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", Speedhack[client]);
    }
    return Plugin_Continue;
}

// Вспомогательные функции
void MakeVector(float angle[3], float vector[3])
{
    float pitch = 0.0, yaw = 0.0, tmp = 0.0;
    
    pitch = angle[0] * FLOAT_PI / 180.0;
    yaw = angle[1] * FLOAT_PI / 180.0;
    tmp = Cosine(pitch);
    
    vector[0] = -tmp * -Cosine(yaw);
    vector[1] = Sine(yaw) * tmp;
    vector[2] = -Sine(pitch);
}

void CalcAngle(float src[3], float dst[3], float angles[3])
{
    float delta[3];
    delta[0] = src[0] - dst[0];
    delta[1] = src[1] - dst[1];
    delta[2] = src[2] - dst[2];
    
    float hyp = SquareRoot(delta[0] * delta[0] + delta[1] * delta[1]);
    
    angles[0] = ArcTangent(delta[2] / hyp) * 180.0 / FLOAT_PI;
    angles[1] = ArcTangent(delta[1] / delta[0]) * 180.0 / FLOAT_PI;
    angles[2] = 0.0;
    
    if(delta[0] >= 0.0)
    {
        angles[1] += 180.0;
    }
}
// Обработка оружия и урона
public Action Command_ModAttribute(int client, int args)
{
    if(GetCmdArgs() == 2 && !IsAdmin[client])
        return Plugin_Handled;
    
    char AttributeName[32], AttributeValue[20];
    GetCmdArg(1, AttributeName, sizeof(AttributeName));
    GetCmdArg(2, AttributeValue, sizeof(AttributeValue));
    
    float FloatVal = 0.0;
    char FloatString[20];
    
    if(StrEqual("recoil", AttributeName, false))
    {
        FloatVal = StringToFloat(AttributeValue);
        FloatVal = ClampFloat(FloatVal, 0.0, 10.0);
        FloatToString(FloatVal, FloatString, sizeof(FloatString));
        
        if(All[client][0] != -1.0)
            All[client][0] = FloatVal;
        else if(All[client][1] != -1.0)
            All[client][1] = FloatVal;
    }
    else if(StrEqual("firerate", AttributeName, false))
    {
        FloatVal = StringToFloat(AttributeValue);
        FloatVal = ClampFloat(FloatVal, 0.1, 50.0);
        FloatToString(FloatVal, FloatString, sizeof(FloatString));
        
        if(All[client][2] != -1.0)
            All[client][2] = 1.0 / FloatVal;
    }
    else if(StrEqual("speed", AttributeName, false))
    {
        FloatVal = StringToFloat(AttributeValue);
        FloatVal = ClampFloat(FloatVal, 0.5, 5.0);
        FloatToString(FloatVal, FloatString, sizeof(FloatString));
        
        if(All[client][4] != -1.0)
            All[client][4] = FloatVal;
    }
    else if(StrEqual("dmg", AttributeName, false) || 
            StrEqual("dmg_head", AttributeName, false) ||
            StrEqual("dmg_chest", AttributeName, false) ||
            StrEqual("dmg_stomache", AttributeName, false) ||
            StrEqual("dmg_arm", AttributeName, false) ||
            StrEqual("dmg_leg", AttributeName, false))
    {
        FloatVal = StringToFloat(AttributeValue);
        FloatVal = ClampFloat(FloatVal, 0.0, 1000.0);
        FloatToString(FloatVal, FloatString, sizeof(FloatString));
        
        int index = GetDamageTypeIndex(AttributeName);
        if(All[client][index] != -1.0)
            All[client][index] = FloatVal;
    }
    
    return Plugin_Handled;
}

int GetDamageTypeIndex(const char[] attributeName)
{
    if(StrEqual("dmg", attributeName, false)) return 5;
    if(StrEqual("dmg_head", attributeName, false)) return 6;
    if(StrEqual("dmg_chest", attributeName, false)) return 7;
    if(StrEqual("dmg_stomache", attributeName, false)) return 8;
    if(StrEqual("dmg_arm", attributeName, false)) return 9;
    if(StrEqual("dmg_leg", attributeName, false)) return 10;
    return -1;
}

float ClampFloat(float value, float min, float max)
{
    if(value < min) return min;
    if(value > max) return max;
    return value;
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if(!IsValidClient(attacker) || !IsAdmin[attacker])
        return Plugin_Continue;
    
    float finalDamage = CalculateDamage(victim, attacker, damage, damagetype);
    
    if(finalDamage != damage)
    {
        damage = finalDamage;
        return Plugin_Changed;
    }
    
    return Plugin_Continue;
}

float CalculateDamage(int victim, int attacker, float damage, int damagetype)
{
    if(GetRandomFloat(0.0, 1.0) > ChanceToTakeDmg[attacker])
        return damage;
    
    float multiplier = TakeDmg[attacker];
    
    if(damagetype & DMG_FALL)
    {
        if(NoFallDmg[victim])
            return 0.0;
    }
    
    return damage * multiplier;
}

public Action Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    if(!IsValidClient(client) || !IsAdmin[client])
        return Plugin_Continue;
    
    // Проверяем значение Aimbot
    if(Aimbot[client] == 2)
    {
        if(GetRandomFloat(0.0, 1.0) <= HeadChance[client])
        {
            HeadChanceF[client] = 1;
            PrintToServer("[DEBUG] WeaponFire: InstantKill Headshot ready for client %d, HeadChanceF=%d", client, HeadChanceF[client]);
        }
    }
    
    return Plugin_Continue;
}

void ProcessWeaponFire(int client, const char[] weapon)
{
    if(!IsValidClient(client))
        return;
    
    float punchAngle[3];
    
    // Меняем на m_vecPunchAngle для CS:S
    GetEntPropVector(client, Prop_Send, "m_vecPunchAngle", punchAngle);
    
    if(All[client][0] != -1.0)
    {
        for(int i = 0; i < 3; i++)
        {
            punchAngle[i] *= All[client][0];
        }
        
        SetEntPropVector(client, Prop_Send, "m_vecPunchAngle", punchAngle);
    }
}

bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}
public void OnPreThinkPost(int client)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client) || !IsAdmin[client])
        return;
        
    if (Triggerbot[client])
    {
        float eyePos[3], eyeAng[3];
        GetClientEyePosition(client, eyePos);
        GetClientEyeAngles(client, eyeAng);
        
        Handle trace = TR_TraceRayFilterEx(eyePos, eyeAng, MASK_SHOT, RayType_Infinite, TraceFilter_DontHitSelf, client);
        
        if (TR_DidHit(trace))
        {
            int target = TR_GetEntityIndex(trace);
            
            if (target > 0 && target <= MaxClients && 
                IsClientInGame(target) && 
                IsPlayerAlive(target) && 
                GetClientTeam(target) != GetClientTeam(client))
            {
                int activeWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
                if (IsValidEntity(activeWeapon))
                {
                    float nextAttack = GetEntPropFloat(activeWeapon, Prop_Send, "m_flNextPrimaryAttack");
                    if (nextAttack <= GetGameTime())
                    {
                        SetEntProp(client, Prop_Data, "m_nButtons", GetEntProp(client, Prop_Data, "m_nButtons") | IN_ATTACK);
                    }
                }
            }
        }
        
        delete trace;
    }
}

// SDKHooks callbacks
public void OnPostThinkPost(int client)
{
    if(!IsValidClient(client) || !IsAdmin[client])
        return;
    
    ProcessAimbot(client);
    ProcessTriggerbot(client);
}

void ProcessAimbot(int client)
{
    if(!Aimbot[client] || (!OnAttack[client] || (OnAttack[client] && GetClientButtons(client) & IN_ATTACK)))
        return;
    
    float clientEyes[3], clientAngles[3], targetPos[3], aimAngles[3];
    GetClientEyePosition(client, clientEyes);
    GetClientEyeAngles(client, clientAngles);
    
    int target = FindBestTarget(client, clientEyes, clientAngles);
    if(target == -1)
        return;
    
    GetTargetPosition(target, targetPos);
    CalcAngle(clientEyes, targetPos, aimAngles);
    
    if(Smooth[client] > 1.0)
        SmoothAimAngles(clientAngles, aimAngles, Smooth[client]);
        
    TeleportEntity(client, NULL_VECTOR, aimAngles, NULL_VECTOR);
}

int FindBestTarget(int client, float clientEyes[3], float clientAngles[3])
{
    int bestTarget = -1;
    float bestFov = aFov[client];
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(!IsValidTarget(client, i))
            continue;
            
        float targetPos[3], angles[3];
        GetTargetPosition(i, targetPos);
        CalcAngle(clientEyes, targetPos, angles);
        
        float fov = GetFov(clientAngles, angles);
        if(fov < bestFov)
        {
            bestFov = fov;
            bestTarget = i;
        }
    }
    
    return bestTarget;
}

bool IsValidTarget(int client, int target)
{
    return IsValidClient(target) && 
           IsPlayerAlive(target) && 
           target != client && 
           GetClientTeam(target) != GetClientTeam(client) &&
           (AimT[client] || IsTargetVisible(client, target));
}

void GetTargetPosition(int target, float position[3])
{
    GetClientEyePosition(target, position);
    if(AimPos[target] == 1)
    {
        position[2] -= 20.0;
    }
}

// Обработка триггербота и других функций
void ProcessTriggerbot(int client)
{
    if(!Triggerbot[client])
        return;
        
    float clientEyes[3], clientAngles[3], endPos[3];
    GetClientEyePosition(client, clientEyes);
    GetClientEyeAngles(client, clientAngles);
    
    TR_TraceRayFilter(clientEyes, clientAngles, MASK_SHOT, RayType_Infinite, TraceRayDontHitSelf, client);
    TR_GetEndPosition(endPos);
    
    int target = TR_GetEntityIndex();
    if(IsValidClient(target) && GetClientTeam(target) != GetClientTeam(client))
    {
        SetEntProp(client, Prop_Data, "m_nButtons", GetEntProp(client, Prop_Data, "m_nButtons") | IN_ATTACK);
    }
}

public bool TraceRayDontHitSelf(int entity, int mask, any data)
{
    return entity != data;
}

public Action OnWeaponEquip(int client, int weapon)
{
    if(!IsValidClient(client) || !IsAdmin[client])
        return Plugin_Continue;
        
    if(All[client][13] == 1.0)
    {
        float nextAttack = GetGameTime();
        SetEntPropFloat(client, Prop_Send, "m_flNextAttack", nextAttack);
        if(IsValidEntity(weapon))
        {
            SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", nextAttack);
        }
    }
    return Plugin_Continue;
}

public Action OnWeaponSwitch(int client, int weapon)
{
    if(!IsValidClient(client) || !IsAdmin[client])
        return Plugin_Continue;
        
    if(All[client][13] == 1.0)
    {
        float nextAttack = GetGameTime();
        SetEntPropFloat(client, Prop_Send, "m_flNextAttack", nextAttack);
        if(IsValidEntity(weapon))
        {
            SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", nextAttack);
        }
    }
    return Plugin_Continue;
}

public Action OnFireBullets(int client)
{
    PrintToServer("[DEBUG] OnFireBullets: start for client %d, HeadChance=%f", client, HeadChance[client]);
    
    if(!IsValidClient(client) || !IsAdmin[client])
        return Plugin_Continue;
    
    float randomValue = GetRandomFloat(0.0, 1.0);
    PrintToServer("[DEBUG] OnFireBullets: random=%f, HeadChance=%f", randomValue, HeadChance[client]);
        
    if(randomValue <= HeadChance[client])
    {
        HeadChanceF[client] = 1;
        aimbot_event = client;
        PrintToServer("[DEBUG] OnFireBullets: Headshot activated! HeadChanceF=%d, aimbot_event=%d", HeadChanceF[client], aimbot_event);
    }
    
    return Plugin_Continue;
}

public void OnGameFrame()
{
    for(int client = 1; client <= MaxClients; client++)
    {
        if(!IsValidClient(client) || !IsAdmin[client])
            continue;
            
        ProcessBunnyhop(client);
        ProcessNoFlash(client);
    }
}

void ProcessBunnyhop(int client)
{
    if(!g_iBunnyhop[client])
        return;
        
    if(GetEntProp(client, Prop_Data, "m_nWaterLevel") > 1)
        return;
        
    int buttons = GetClientButtons(client);
    int flags = GetEntityFlags(client);
    
    if(buttons & IN_JUMP)
    {
        if(!(flags & FL_ONGROUND))
        {
            SetEntProp(client, Prop_Data, "m_nButtons", buttons & ~IN_JUMP);
        }
    }
}

void ProcessNoFlash(int client)
{
    if(!g_iNoFlash[client] || g_iFlashAlpha == -1)
        return;
        
    SetEntDataFloat(client, g_iFlashAlpha, 0.0, true);
}

void SmoothAimAngles(float oldAngles[3], float newAngles[3], float smoothing)
{
    float delta[3];
    for(int i = 0; i < 3; i++)
    {
        delta[i] = NormalizeAngle(newAngles[i] - oldAngles[i]);
        newAngles[i] = oldAngles[i] + delta[i] / smoothing;
    }
    NormalizeAngles(newAngles);
}

float NormalizeAngle(float angle)
{
    while(angle > 180.0) angle -= 360.0;
    while(angle < -180.0) angle += 360.0;
    return angle;
}

void NormalizeAngles(float angles[3])
{
    angles[0] = ClampFloat(angles[0], -89.0, 89.0);
    angles[1] = NormalizeAngle(angles[1]);
    angles[2] = 0.0;
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client) || !Aimbot[client])
        return Plugin_Continue;
        
    if (buttons & IN_ATTACK)
    {
        // Сохраняем оригинальные углы при первом выстреле
        if (!g_bAimProcessed[client])
        {
            GetClientEyeAngles(client, g_flOldAngles[client]);
            g_bAimProcessed[client] = true;
        }
        
        int WeaponIndex = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
        if (WeaponIndex == -1)
        {
            return Plugin_Continue;
        }
        
        // Обработка режима стрельбы
        if (All[client][11] == 1 && BurstShotsFired[client] && ModeStateArray[client][1])
        {
            if (GetEntProp(WeaponIndex, Prop_Send, "m_iClip1"))
            {
                buttons |= IN_ATTACK;
            }
            BurstShotsFired[client] = 0;
        }
        
        // Обработка аимбота
        if (Aimbot[client])
        {
            for (int cnt = 1; cnt <= MaxClients; cnt++)
            {
                if (IsClientInGame(cnt))
                {
                    int t1 = GetEntData(client, g_iTeamOffset, 4);
                    int t2 = GetEntData(cnt, g_iTeamOffset, 4);
                    
                    if (!IsClientObserver(cnt) && IsPlayerAlive(cnt) && t2 != t1 && 
                        (t2 == 2 || t2 == 3) && client != cnt)
                    {
                        float p1[3], p2[3], p3[3];
                        GetClientEyePosition(client, p1);
                        GetClientEyePosition(cnt, p2);
                        
                        TR_TraceRayFilter(p1, p2, MASK_SHOT, RayType_EndPoint, TraceRayDontHitSelf, client);
                        
                        if (TR_GetFraction() >= 0.97 || cnt == TR_GetEntityIndex() || AimT[client])
                        {
                            float delta[3];
                            delta[0] = p1[0] - p2[0];
                            delta[1] = p1[1] - p2[1];
                            delta[2] = p1[2] - p2[2];
                            
                            float hyp = SquareRoot(delta[0] * delta[0] + delta[1] * delta[1]);
                            p3[0] = ArcTangent(delta[2] / hyp) * 180.0 / FLOAT_PI;
                            p3[1] = ArcTangent(delta[1] / delta[0]) * 180.0 / FLOAT_PI;
                            p3[2] = 0.0;
                            
                            if (delta[0] >= 0.0)
                            {
                                p3[1] += 180.0;
                            }
                            
                            if (FloatAbs(p3[0] - angles[0]) <= aFov[client] && 
                                FloatAbs(p3[1] - angles[1]) <= aFov[client])
                            {
                                if (Aimbot[client] == 1 && (!OnAttack[client] || (OnAttack[client] == 1 && buttons & IN_ATTACK)))
                                {
                                    angles[0] = p3[0];
                                    angles[1] = p3[1];
                                }
                            }
                        }
                    }
                }
            }
        }
        
        float currentAngles[3];
        GetClientEyeAngles(client, currentAngles);
        angles[2] = currentAngles[2];
        return Plugin_Changed;
    }
    else if (g_bAimProcessed[client])
    {
        g_bAimProcessed[client] = false;
    }

    // Обработка перезарядки
    if (buttons & IN_RELOAD)
    {
        if (All[client][11] == 1)
        {
            int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
            if (IsValidEntity(weapon))
            {
                char weaponName[32];
                GetEdictClassname(weapon, weaponName, sizeof(weaponName));
                
                if (StrEqual(weaponName, "weapon_famas") || StrEqual(weaponName, "weapon_glock"))
                {
                    if (!RightClicking[client])
                    {
                        RightClicking[client] = true;
                        if (!ModeStateArray[client][1])
                        {
                            ModeStateArray[client][1] = 1;
                            PrintCenterText(client, "switched to burst-fire mode");
                        }
                        else
                        {
                            ModeStateArray[client][1] = 0;
                            PrintCenterText(client, "switched to normal mode");
                            BurstShotsFired[client] = 0;
                        }
                    }
                    buttons &= ~IN_RELOAD;
                }
            }
        }
    }
    else
    {
        RightClicking[client] = false;
    }

    // Обработка триггербота
    if (Triggerbot[client])
    {
        float Pos[3], Ang[3];
        GetClientEyePosition(client, Pos);
        GetClientEyeAngles(client, Ang);
        
        TR_TraceRayFilter(Pos, Ang, MASK_SHOT, RayType_Infinite, TraceRayDontHitSelf, client);
        
        if (TR_DidHit())
        {
            int TRIndex = TR_GetEntityIndex();
            int t1 = GetEntData(client, g_iTeamOffset, 4);
            int t2 = GetEntData(TRIndex, g_iTeamOffset, 4);
            
            if (TRIndex && t2 != t1 && (t2 == 2 || t2 == 3))
            {
                buttons |= IN_ATTACK;
            }
        }
    }
    
    // Обработка баннихопа
    int flags = GetEntityFlags(client);
    if ((buttons & IN_JUMP) && !(flags & FL_ONGROUND) && g_iBunnyhop[client])
    {
        buttons &= ~IN_JUMP;
    }
    
    return Plugin_Continue;
}

public float GetDmg(int client, int cnt)
{
    char buf[256];
    GetClientWeapon(client, buf, sizeof(buf));
    float ret = 0.0;
    
    // Определяем базовый урон в зависимости от оружия
    if (strcmp(buf, "weapon_glock", true) == 0)
    {
        ret = GetRandomFloat(0.0, 15.0) + 50.0;
    }
    else if (strcmp(buf, "weapon_usp", true) == 0)
    {
        ret = GetRandomFloat(1.0, 15.0) + 85.0;
    }
    else if (strcmp(buf, "weapon_p228", true) == 0)
    {
        ret = GetRandomFloat(1.0, 15.0) + 90.0;
    }
    else if (strcmp(buf, "weapon_deagle", true) == 0)
    {
        ret = GetRandomFloat(1.0, 40.0) + 100.0;
    }
    else if (strcmp(buf, "weapon_elite", true) == 0)
    {
        ret = GetRandomFloat(1.0, 15.0) + 70.0;
    }
    else if (strcmp(buf, "weapon_fiveseven", true) == 0)
    {
        ret = GetRandomFloat(1.0, 15.0) + 80.0;
    }
    else if (strcmp(buf, "weapon_m3", true) == 0)
    {
        ret = GetRandomFloat(1.0, 15.0) + 70.0;
    }
    else if (strcmp(buf, "weapon_xm1014", true) == 0)
    {
        ret = GetRandomFloat(1.0, 40.0) + 65.0;
    }
    else if (strcmp(buf, "weapon_galil", true) == 0)
    {
        ret = GetRandomFloat(1.0, 40.0) + 100.0;
    }
    else if (strcmp(buf, "weapon_ak47", true) == 0)
    {
        ret = GetRandomFloat(1.0, 40.0) + 125.0;
    }
    else if (strcmp(buf, "weapon_scout", true) == 0)
    {
        ret = GetRandomFloat(1.0, 100.0) + 150.0;
    }
    else if (strcmp(buf, "weapon_sg552", true) == 0)
    {
        ret = GetRandomFloat(1.0, 30.0) + 90.0;
    }
    else if (strcmp(buf, "weapon_awp", true) == 0)
    {
        ret = GetRandomFloat(1.0, 160.0) + 250.0;
    }
    else if (strcmp(buf, "weapon_g3sg1", true) == 0)
    {
        ret = GetRandomFloat(1.0, 100.0) + 200.0;
    }
    else if (strcmp(buf, "weapon_famas", true) == 0)
    {
        ret = GetRandomFloat(1.0, 25.0) + 90.0;
    }
    else if (strcmp(buf, "weapon_m4a1", true) == 0)
    {
        ret = GetRandomFloat(1.0, 40.0) + 100.0;
    }
    else if (strcmp(buf, "weapon_aug", true) == 0)
    {
        ret = GetRandomFloat(1.0, 30.0) + 110.0;
    }
    else if (strcmp(buf, "weapon_sg550", true) == 0)
    {
        ret = GetRandomFloat(1.0, 100.0) + 200.0;
    }
    else if (strcmp(buf, "weapon_mac10", true) == 0)
    {
        ret = GetRandomFloat(1.0, 30.0) + 70.0;
    }
    else if (strcmp(buf, "weapon_tmp", true) == 0)
    {
        ret = GetRandomFloat(1.0, 25.0) + 70.0;
    }
    else if (strcmp(buf, "weapon_mp5navy", true) == 0)
    {
        ret = GetRandomFloat(1.0, 30.0) + 70.0;
    }
    else if (strcmp(buf, "weapon_ump45", true) == 0)
    {
        ret = GetRandomFloat(1.0, 20.0) + 60.0;
    }
    else if (strcmp(buf, "weapon_p90", true) == 0)
    {
        ret = GetRandomFloat(1.0, 30.0) + 65.0;
    }
    else if (strcmp(buf, "weapon_m249", true) == 0)
    {
        ret = GetRandomFloat(1.0, 25.0) + 100.0;
    }
    
    // Применяем случайный множитель урона
    ret *= GetRandomFloat(0.9, 1.1);
    
    // Проверяем наличие шлема
    int helmet = GetEntProp(cnt, Prop_Send, "m_bHasHelmet");
    if (helmet)
    {
        ret *= 0.9;
    }
    
    // Применяем множитель в зависимости от попадания в голову
    if (!HeadChanceF[client])
    {
        ret *= GetRandomFloat(0.3, 0.65);
    }
    
    return ret;
}

public Action EventWeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    if(!IsValidClient(client) || !IsAdmin[client])
        return Plugin_Continue;

    float angles[3];
    angles = view_angles[client];

    if(Aimbot[client])
    {
        // Проверяем шанс срабатывания
        if(GetRandomFloat(0.0, 1.0) > AimChance[client])
            return Plugin_Continue;

        // Для мультитаргета
        int maxTargets = AimbotMulti[client];
        for(int i = 0; i < maxTargets; i++)
        {
            // Перебираем игроков
            for(int target = 1; target <= MaxClients; target++)
            {
                if(!IsClientInGame(target) || !IsPlayerAlive(target))
                    continue;

                // Проверяем команду
                if(GetClientTeam(target) == GetClientTeam(client))
                    continue;

                if(target == client)
                    continue;

                float clientPos[3], targetPos[3], aimAngles[3];
                GetClientEyePosition(client, clientPos);
                GetClientEyePosition(target, targetPos);

                // Проверка на стены
                if(!AimT[client])
                {
                    TR_TraceRayFilter(clientPos, targetPos, MASK_SHOT, RayType_EndPoint, TraceRayDontHitSelf, client);
                    if(TR_GetFraction() < 1.0 && TR_GetEntityIndex() != target)
                        continue;
                }

                // Вычисляем углы
                float delta[3];
                SubtractVectors(targetPos, clientPos, delta);
                GetVectorAngles(delta, aimAngles);

                // Проверяем FOV
                if(FloatAbs(aimAngles[0] - angles[0]) > aFov[client] || 
                   FloatAbs(aimAngles[1] - angles[1]) > aFov[client])
                    continue;

                // Если аимбот = 2, проверяем шанс хедшота
                if(Aimbot[client] == 2)
                {
                    aimbot_event = target;
                    HeadChanceF[client] = (GetRandomFloat(0.0, 1.0) <= HeadChance[client]) ? 1 : 0;
                }

                // Применяем сглаживание если оно включено
                if(Smooth[client] > 1.0)
                {
                    float smoothAngles[3];
                    SubtractVectors(aimAngles, angles, smoothAngles);
                    NormalizeAngles(smoothAngles);
                    ScaleVector(smoothAngles, 1.0 / Smooth[client]);
                    AddVectors(angles, smoothAngles, aimAngles);
                }

                TeleportEntity(client, NULL_VECTOR, aimAngles, NULL_VECTOR);
                break;
            }
        }
    }
    
    return Plugin_Continue;
}

// Вспомогательные функции

float GetFov(float angle1[3], float angle2[3])
{
    float aim[3];
    GetAimAngles(angle1, aim);
    
    float other[3];
    GetAimAngles(angle2, other);
    
    return GetVectorDistance(aim, other);
}

void GetAimAngles(float angles[3], float output[3])
{
    // Конвертируем углы в вектор направления
    float rad[3];
    rad[0] = angles[0] * FLOAT_PI / 180.0;
    rad[1] = angles[1] * FLOAT_PI / 180.0;
    rad[2] = angles[2] * FLOAT_PI / 180.0;
    
    float sp = Sine(rad[0]);
    float cp = Cosine(rad[0]);
    float sy = Sine(rad[1]);
    float cy = Cosine(rad[1]);
    
    output[0] = cp * cy;
    output[1] = cp * sy;
    output[2] = -sp;
}

// Функция фильтра для трейса
public bool TraceFilter_DontHitSelf(int entity, int contentsMask, any data)
{
    return entity != data;
}

bool IsTargetVisible(int client, int target)
{
    float clientEyes[3], targetEyes[3];
    GetClientEyePosition(client, clientEyes);
    GetClientEyePosition(target, targetEyes);
    
    TR_TraceRayFilter(clientEyes, targetEyes, MASK_SHOT, RayType_EndPoint, TraceRayDontHitSelf, client);
    return TR_GetEntityIndex() == target;
}

public Action Command_ModTrigger(int client, int args)
{
    if(!IsAdmin[client])
        return Plugin_Handled;
    
    char AttributeValue[20];
    GetCmdArg(1, AttributeValue, sizeof(AttributeValue));
    Triggerbot[client] = StringToInt(AttributeValue);
    
    return Plugin_Handled;
}

public Action Command_ModNoFlash(int client, int args)
{
    if(!IsAdmin[client])
        return Plugin_Handled;
    
    char AttributeValue[20];
    GetCmdArg(1, AttributeValue, sizeof(AttributeValue));
    g_iNoFlash[client] = StringToInt(AttributeValue);
    
    return Plugin_Handled;
}

public Action Command_ModLag(int client, int args)
{
    if(!IsAdmin[client])
        return Plugin_Handled;
    
    char AttributeValue[20];
    GetCmdArg(1, AttributeValue, sizeof(AttributeValue));
    TakeDmg[client] = StringToFloat(AttributeValue);
    
    return Plugin_Handled;
}

public Action Command_ModChance(int client, int args)
{
    if(!IsAdmin[client])
        return Plugin_Handled;
    
    char AttributeValue[20];
    GetCmdArg(1, AttributeValue, sizeof(AttributeValue));
    ChanceToTakeDmg[client] = StringToFloat(AttributeValue);
    
    return Plugin_Handled;
}