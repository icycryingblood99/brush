#pragma semicolon 1

#include <sourcemod>
#include <cstrike>
#include <sdktools>

#define MAXSLOTS 66

// Extension declarations
public Extension:__ext_core = 
{
    name = "Core",
    file = "core",
    autoload = 0,
    required = 0
};

public Extension:__ext_sdktools = 
{
    name = "SDKTools",
    file = "sdktools.ext",
    autoload = 1,
    required = 1
};

public Extension:__ext_cstrike = 
{
    name = "cstrike",
    file = "games/game.cstrike.ext",
    autoload = 0,
    required = 1
};

public Plugin:myinfo = 
{
    name = "CSS BRush: v34",
    description = "",
    author = "TnTSCS & Danyas",
    version = "19.09.2016",
    url = ""
};

// Переменные
new String:CTag[6][] = 
{
    "{default}",
    "{green}",
    "{lightgreen}",
    "{red}",
    "{blue}",
    "{olive}"
};

new String:CTagCode[6][16] = 
{
    "\x01",
    "\x04",
    "\x03",
    "\x03",
    "\x03",
    "\x05"
};

new bool:CTagReqSayText2[6] = {false, false, true, true, true, false};
new bool:CEventIsHooked;
new bool:CSkipList[MAXSLOTS];
new bool:CProfile_Colors[6] = {true, true, false, false, false, false};
new CProfile_TeamIndex[6] = {-1, ...};
new bool:CProfile_SayText2;

// Игровые переменные
new CTKiller;
new PlayerKilledCT[MAXSLOTS];
new CTImmune[MAXSLOTS];
new SwitchingPlayer[MAXSLOTS];
new bool:PlayerSwitchable[MAXSLOTS];
new Handle:ClientTimer[MAXSLOTS];
new Handle:p_FreezeTime[MAXSLOTS];

// Настройки плагина
new bool:UseWeaponRestrict = true;
new bool:AllowHEGrenades;
new bool:AllowFlashBangs;
new bool:AllowSmokes;
new bool:GameIsLive;
new bool:Enabled = true;
new bool:ManageBots = true;
new bool:FillBots;
new bool:UseConfigs;

// Таймеры
new Float:CTFreezeTime;
new Float:TFreezeTime;
new Handle:LiveTimer;
new Handle:brush_botquota;

// Переменные статуса
new bool:g_bGameStarted;
new g_iRoundNumber;
new Handle:g_hSlotMenuTimers[MAXSLOTS];
new bool:g_bBlockTeamChange[MAXSLOTS];
new bool:g_bWaitingForSlot[MAXSLOTS];
new bool:g_bForceStarted;
new g_iSelectionsRemaining;
new g_iPlanterUserId;
new bool:g_bSelectionInProgress;

// AWP и раундовые переменные
new bool:CTAwps;
new CTAwpNumber;
new bool:TAwps;
new TAwpNumber;
new FreezeTime;
new MenuTime;
new CTScore;
new TScore;
new killers;
new g_BombsiteB = -1;
new g_BombsiteA = -1;
new numSwitched;
new bot_quota;
new the_bomb = -1;
new roundend_mode;
new tawpno;
new ctawpno;
new bool:IsPlayerFrozen[MAXSLOTS];

// Бомбсайт и модели
new String:s_bombsite[4] = "B";
new String:ctmodels[4][112] = 
{
    "models/player/ct_urban.mdl",
    "models/player/ct_gsg9.mdl",
    "models/player/ct_sas.mdl",
    "models/player/ct_gign.mdl"
};

new String:tmodels[4][] = 
{
    "models/player/t_phoenix.mdl",
    "models/player/t_leet.mdl",
    "models/player/t_arctic.mdl",
    "models/player/t_guerilla.mdl"
};


// Native interface
stock MarkOptionalNatives()
{
    MarkNativeAsOptional("GetFeatureStatus");
    MarkNativeAsOptional("RequireFeature");
    MarkNativeAsOptional("AddCommandListener");
    MarkNativeAsOptional("RemoveCommandListener");
    VerifyCoreVersion();
}

bool:operator!=(Float:,Float:)(Float:oper1, Float:oper2)
{
	return FloatCompare(oper1, oper2) != 0;
}

bool:operator<=(Float:,Float:)(Float:oper1, Float:oper2)
{
	return FloatCompare(oper1, oper2) <= 0;
}

bool:StrEqual(String:str1[], String:str2[], bool:caseSensitive)
{
	return strcmp(str1, str2, caseSensitive) == 0;
}

Handle:StartMessageOne(String:msgname[], client, flags)
{
	new players[1];
	players[0] = client;
	return StartMessage(msgname, players, 1, flags);
}

PrintCenterTextAll(String:format[])
{
	decl String:buffer[192];
	new i = 1;
	while (i <= MaxClients)
	{
		if (IsClientInGame(i))
		{
			SetGlobalTransTarget(i);
			VFormat(buffer, 192, format, 2);
			PrintCenterText(i, "%s", buffer);
		}
		i++;
	}
	return 0;
}

GetEntSendPropOffs(ent, String:prop[], bool:actual)
{
	decl String:cls[64];
	if (!GetEntityNetClass(ent, cls, 64))
	{
		return -1;
	}
	if (actual)
	{
		return FindSendPropInfo(cls, prop, 0, 0, 0);
	}
	return FindSendPropOffs(cls, prop);
}

bool:GetEntityClassname(entity, String:clsname[], maxlength)
{
	return !!GetEntPropString(entity, PropType:1, "m_iClassname", clsname, maxlength, 0);
}

void SetEntityRenderColor(int entity, int r, int g, int b, int a)
{
    static bool gotconfig;
    static char prop[32];
    
    if (!gotconfig)
    {
        Handle gc = LoadGameConfigFile("core.games");
        bool exists = GameConfGetKeyValue(gc, "m_clrRender", prop, sizeof(prop));
        delete gc;
        
        if (!exists)
            strcopy(prop, sizeof(prop), "m_clrRender");
            
        gotconfig = true;
    }
    
    int offset = GetEntSendPropOffs(entity, prop, false);
    if (offset <= 0)
        ThrowError("SetEntityRenderColor not supported by this mod");
    
    SetEntData(entity, offset, r, 1, true);
    SetEntData(entity, offset + 1, g, 1, true);
    SetEntData(entity, offset + 2, b, 1, true);
    SetEntData(entity, offset + 3, a, 1, true);
}

void EmitSoundToClient(int client, const char[] sample, int entity = SOUND_FROM_PLAYER, 
                      int channel = SNDCHAN_AUTO, int level = SNDLEVEL_NORMAL, 
                      int flags = SND_NOFLAGS, float volume = SNDVOL_NORMAL, 
                      int pitch = SNDPITCH_NORMAL, int speakerentity = -1,
                      const float origin[3] = NULL_VECTOR, const float dir[3] = NULL_VECTOR, 
                      bool updatePos = true, float soundtime = 0.0)
{
    int clients[1];
    clients[0] = client;
    
    if (entity == -2)
        entity = client;
        
    EmitSound(clients, 1, sample, entity, channel, level, flags, volume, pitch, speakerentity, origin, dir, updatePos, soundtime);
}

CPrintToChat(client, String:szMessage[])
{
	new var1;
	if (client <= 0 || client > MaxClients)
	{
		ThrowError("Invalid client index %d", client);
	}
	if (!IsClientInGame(client))
	{
		ThrowError("Client %d is not in game", client);
	}
	decl String:szBuffer[252];
	decl String:szCMessage[252];
	SetGlobalTransTarget(client);
	Format(szBuffer, 250, "\x01%s", szMessage);
	VFormat(szCMessage, 250, szBuffer, 3);
	new index = CFormat(szCMessage, 250, -1);
	if (index == -1)
	{
		PrintToChat(client, szCMessage);
	}
	else
	{
		CSayText2(client, index, szCMessage);
	}
	return 0;
}

CPrintToChatAll(String:szMessage[])
{
	decl String:szBuffer[252];
	new i = 1;
	while (i <= MaxClients)
	{
		new var1;
		if (IsClientInGame(i) && !IsFakeClient(i) && !CSkipList[i])
		{
			SetGlobalTransTarget(i);
			VFormat(szBuffer, 250, szMessage, 2);
			CPrintToChat(i, szBuffer);
		}
		CSkipList[i] = 0;
		i++;
	}
	return 0;
}

CFormat(String:szMessage[], maxlength, author)
{
	if (!CEventIsHooked)
	{
		CSetupProfile();
		HookEvent("server_spawn", CEvent_MapStart, EventHookMode:2);
		CEventIsHooked = true;
	}
	new iRandomPlayer = -1;
	if (author != -1)
	{
		if (CProfile_SayText2)
		{
			ReplaceString(szMessage, maxlength, "{teamcolor}", "\x03", true);
			iRandomPlayer = author;
		}
		else
		{
			ReplaceString(szMessage, maxlength, "{teamcolor}", CTagCode[1], true);
		}
	}
	else
	{
		ReplaceString(szMessage, maxlength, "{teamcolor}", "", true);
	}
	new i;
	while (i < 6)
	{
		if (!(StrContains(szMessage, CTag[i], true) == -1))
		{
			if (!CProfile_Colors[i])
			{
				ReplaceString(szMessage, maxlength, CTag[i], CTagCode[1], true);
			}
			else
			{
				if (!CTagReqSayText2[i])
				{
					ReplaceString(szMessage, maxlength, CTag[i], CTagCode[i], true);
				}
				if (!CProfile_SayText2)
				{
					ReplaceString(szMessage, maxlength, CTag[i], CTagCode[1], true);
				}
				if (iRandomPlayer == -1)
				{
					iRandomPlayer = CFindRandomPlayerByTeam(CProfile_TeamIndex[i]);
					if (iRandomPlayer == -2)
					{
						ReplaceString(szMessage, maxlength, CTag[i], CTagCode[1], true);
					}
					else
					{
						ReplaceString(szMessage, maxlength, CTag[i], CTagCode[i], true);
					}
				}
				ThrowError("Using two team colors in one message is not allowed");
			}
		}
		i++;
	}
	return iRandomPlayer;
}

CFindRandomPlayerByTeam(color_team)
{
	if (color_team)
	{
		new i = 1;
		while (i <= MaxClients)
		{
			new var1;
			if (IsClientInGame(i) && color_team == GetClientTeam(i))
			{
				return i;
			}
			i++;
		}
		return -2;
	}
	return 0;
}

CSayText2(client, author, String:szMessage[])
{
	new Handle:hBuffer = StartMessageOne("SayText2", client, 0);
	BfWriteByte(hBuffer, author);
	BfWriteByte(hBuffer, 1);
	BfWriteString(hBuffer, szMessage);
	EndMessage();
	return 0;
}

CSetupProfile()
{
	decl String:szGameName[32];
	GetGameFolderName(szGameName, 30);
	if (StrEqual(szGameName, "cstrike", false))
	{
		CProfile_Colors[2] = 1;
		CProfile_Colors[3] = 1;
		CProfile_Colors[4] = 1;
		CProfile_Colors[5] = 1;
		CProfile_TeamIndex[2] = 0;
		CProfile_TeamIndex[3] = 2;
		CProfile_TeamIndex[4] = 3;
		CProfile_SayText2 = true;
	}
	else
	{
		if (StrEqual(szGameName, "tf", false))
		{
			CProfile_Colors[2] = 1;
			CProfile_Colors[3] = 1;
			CProfile_Colors[4] = 1;
			CProfile_Colors[5] = 1;
			CProfile_TeamIndex[2] = 0;
			CProfile_TeamIndex[3] = 2;
			CProfile_TeamIndex[4] = 3;
			CProfile_SayText2 = true;
		}
		new var1;
		if (StrEqual(szGameName, "left4dead", false) || StrEqual(szGameName, "left4dead2", false))
		{
			CProfile_Colors[2] = 1;
			CProfile_Colors[3] = 1;
			CProfile_Colors[4] = 1;
			CProfile_Colors[5] = 1;
			CProfile_TeamIndex[2] = 0;
			CProfile_TeamIndex[3] = 3;
			CProfile_TeamIndex[4] = 2;
			CProfile_SayText2 = true;
		}
		if (StrEqual(szGameName, "hl2mp", false))
		{
			if (GetConVarBool(FindConVar("mp_teamplay")))
			{
				CProfile_Colors[3] = 1;
				CProfile_Colors[4] = 1;
				CProfile_TeamIndex[3] = 3;
				CProfile_TeamIndex[4] = 2;
				CProfile_SayText2 = true;
			}
			else
			{
				CProfile_SayText2 = false;
			}
		}
		if (StrEqual(szGameName, "dod", false))
		{
			CProfile_Colors[5] = 1;
			CProfile_SayText2 = false;
		}
		if (GetUserMessageId("SayText2") == -1)
		{
			CProfile_SayText2 = false;
		}
		CProfile_Colors[3] = 1;
		CProfile_Colors[4] = 1;
		CProfile_TeamIndex[3] = 2;
		CProfile_TeamIndex[4] = 3;
		CProfile_SayText2 = true;
	}
	return 0;
}

public Action:CEvent_MapStart(Handle:event, String:name[], bool:dontBroadcast)
{
	CSetupProfile();
	new i = 1;
	while (i <= MaxClients)
	{
		CSkipList[i] = 0;
		i++;
	}
	return Action:0;
}

public OnPluginStart()
{
	
	MarkOptionalNatives();
	new Handle:hRandom;
	new var1 = CreateConVar("sm_brush_version", "19.09.2016", "Version of 'CSS BRush'", 393536, false, 0.0, false, 0.0);
	hRandom = var1;
	HookConVarChange(var1, OnVersionChanged);
	new var2 = CreateConVar("sm_brush_useweaprestrict", "1", "Use this plugin's weapon restrict features?\n1=yes\n0=no - if you are going to use a different weapon restrict plugin", 0, true, 0.0, true, 1.0);
	hRandom = var2;
	HookConVarChange(var2, OnUseWeaponRestrictChanged);
	UseWeaponRestrict = GetConVarBool(hRandom);
	new var3 = CreateConVar("sm_brush_hegrenades", "1", "Allow players to buy/use HEGrenades?\n1=yes\n0=no", 0, true, 0.0, true, 1.0);
	hRandom = var3;
	HookConVarChange(var3, OnHEGrenadesChanged);
	AllowHEGrenades = GetConVarBool(hRandom);
	new var4 = CreateConVar("sm_brush_flashbangs", "0", "Allow players to buy/use FlashBangs?\n1=yes\n0=no", 0, true, 0.0, true, 1.0);
	hRandom = var4;
	HookConVarChange(var4, OnFlashBangsChanged);
	AllowFlashBangs = GetConVarBool(hRandom);
	new var5 = CreateConVar("sm_brush_smokes", "0", "Allow players to buy/use Smoke Grenades?\n1=yes\n0=no", 0, true, 0.0, true, 1.0);
	hRandom = var5;
	HookConVarChange(var5, OnSmokesChanged);
	AllowSmokes = GetConVarBool(hRandom);
	new var6 = CreateConVar("sm_brush_ctawps", "1", "Allow CTs to buy/use AWPs/Autos?\n1=yes\n0=no", 0, true, 0.0, true, 1.0);
	hRandom = var6;
	HookConVarChange(var6, OnCTAwpsChanged);
	CTAwps = GetConVarBool(hRandom);
	new var7 = CreateConVar("sm_brush_ctawpnumber", "1", "If CTs are allowed to buy/use AWPs/Autos, how many should they be limited to?", 0, true, 1.0, true, 3.0);
	hRandom = var7;
	HookConVarChange(var7, OnCTAwpNumberChanged);
	CTAwpNumber = GetConVarInt(hRandom);
	new var8 = CreateConVar("sm_brush_tawps", "0", "Allow Ts to buy/use AWPs/Autos?\n1=yes\n0=no", 0, true, 0.0, true, 1.0);
	hRandom = var8;
	HookConVarChange(var8, OnTAwpsChanged);
	TAwps = GetConVarBool(hRandom);
	new var9 = CreateConVar("sm_brush_tawpnumber", "1", "If Ts are allowed to buy/use AWPs/Autos, how many should they be limited to?", 0, true, 1.0, true, 5.0);
	hRandom = var9;
	HookConVarChange(var9, OnTAwpNumberChanged);
	TAwpNumber = GetConVarInt(hRandom);
	new var10 = FindConVar("mp_freezetime");
	hRandom = var10;
	HookConVarChange(var10, OnFreezeTimeChanged);
	FreezeTime = GetConVarInt(hRandom);
	MenuTime = FreezeTime + 3 / 2;
	new var11 = CreateConVar("sm_brush_enabled", "1", "Is this plugin enabled?", 0, true, 0.0, true, 1.0);
	hRandom = var11;
	HookConVarChange(var11, OnEnabledChanged);
	Enabled = GetConVarBool(hRandom);
	new var12 = CreateConVar("sm_brush_managebots", "1", "Allow BRush to remove bots, if present, when human players join?", 0, true, 0.0, true, 1.0);
	hRandom = var12;
	HookConVarChange(var12, OnManageBotsChanged);
	ManageBots = GetConVarBool(hRandom);
	new var13 = CreateConVar("sm_brush_fillbots", "0", "Allow BRush to maintain 8 players at all times by adding/removing bots?", 0, true, 0.0, true, 1.0);
	hRandom = var13;
	HookConVarChange(var13, OnFillBotsChanged);
	FillBots = GetConVarBool(hRandom);
	new var14 = CreateConVar("sm_brush_usecfgs", "0", "Should BRush execute the brush.live.cfg and brush.notlive.cfg configs (located in cstrike/cfg)?", 0, true, 0.0, true, 1.0);
	hRandom = var14;
	HookConVarChange(var14, OnUseConfigsChanged);
	UseConfigs = GetConVarBool(hRandom);
	new var15 = CreateConVar("sm_brush_ctfreeze", "2.0", "How long should the CTs remain frozen after mp_freezetime has expired?", 0, true, 0.0, true, 25.0);
	hRandom = var15;
	HookConVarChange(var15, OnCTFreezeTimeChanged);
	CTFreezeTime = GetConVarFloat(hRandom);
	new var16 = CreateConVar("sm_brush_tfreeze", "4.0", "How long should the Terrorists remain frozen after mp_freezetime has expired?", 0, true, 0.0, true, 25.0);
	hRandom = var16;
	HookConVarChange(var16, OnTFreezeTimeChanged);
	TFreezeTime = GetConVarFloat(hRandom);
	new var17 = CreateConVar("sm_brush_endmode", "1", "What should happen to players when the round ends and the Terrorists are the winners?\n0 = Nothing\n1 = Teleport alive players back to their spawn\n2 = Give alive players god mode", 0, true, 0.0, true, 2.0);
	hRandom = var17;
	HookConVarChange(var17, OnRoundEndModeChanged);
	roundend_mode = GetConVarInt(hRandom);
	new var18 = CreateConVar("sm_brush_bombsite", "B", "What bomb site should be used?", 0, false, 0.0, false, 0.0);
	hRandom = var18;
	HookConVarChange(var18, OnBombsiteChanged);
	GetConVarString(hRandom, s_bombsite, 2);
	new var19 = FindConVar("bot_quota");
	brush_botquota = var19;
	HookConVarChange(var19, OnBotQuotaChanged);
	bot_quota = GetConVarInt(brush_botquota);
    RegAdminCmd("sm_forcestart", Command_ForceStart, ADMFLAG_GENERIC);
    RegAdminCmd("sm_forcestop", Command_ForceStop, ADMFLAG_GENERIC);
    RemoveBombSites();
	LoadTranslations("brush.phrases");
	HookEvent("bomb_beginplant", Event_BeginBombPlant, EventHookMode:1);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode:1);
	HookEvent("round_end", Event_RoundEnd, EventHookMode:1);
	HookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode:1);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode:0);
	HookEvent("bomb_exploded", Event_BombExploded, EventHookMode:0);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode:1);
	HookEvent("bomb_pickup", Event_BombPickup, EventHookMode:1);
	HookEvent("round_start", Event_RoundStart);
	AddCommandListener(Command_JoinTeam, "jointeam");
	AutoExecConfig(true, "", "sourcemod");
	return 0;
}

public OnConfigsExecuted()
{
	PrecacheSound("buttons/weapon_cant_buy.wav", true);
	return 0;
}

public OnMapStart()
{
    g_bGameStarted = false;
    g_iRoundNumber = 0;
    
    for(new i = 1; i <= MaxClients; i++)
    {
        g_hSlotMenuTimers[i] = INVALID_HANDLE;
        g_bWaitingForSlot[i] = false;
    }
}

public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
    for(new i = 1; i <= MaxClients; i++)
    {
        if(g_hSlotMenuTimers[i] != INVALID_HANDLE)
        {
            KillTimer(g_hSlotMenuTimers[i]);
            g_hSlotMenuTimers[i] = INVALID_HANDLE;
        }
        g_bWaitingForSlot[i] = false;
    }
}

// При отключении игрока
public OnClientDisconnect(client)
{
    if(g_hSlotMenuTimers[client] != INVALID_HANDLE)
    {
        KillTimer(g_hSlotMenuTimers[client]);
        g_hSlotMenuTimers[client] = INVALID_HANDLE;
    }
    g_bWaitingForSlot[client] = false;

    if(g_bGameStarted)
    {
        new team = GetClientTeam(client);
        if(team == CS_TEAM_CT || team == CS_TEAM_T)
        {
            CreateTimer(0.5, Timer_CheckForSpectators);
        }
    }
}

public Action:Timer_CheckForSpectators(Handle:timer)
{
    new tCount = GetTeamClientCount(CS_TEAM_T);
    
    // Если T > 5, не показываем меню
    if(tCount > 5)
        return Plugin_Stop;
        
    for(new i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == CS_TEAM_SPECTATOR)
        {
            ShowSlotAvailableMenu(i);
        }
    }
    
    return Plugin_Stop;
}


void ShowSlotAvailableMenu(client)
{
    new Handle:menu = CreateMenu(MenuHandler_SlotAvailable);
    SetMenuTitle(menu, "Появился свободный слот! У вас 10 секунд на выбор");
    
    new tCount = GetTeamClientCount(CS_TEAM_T);
    new ctCount = GetTeamClientCount(CS_TEAM_CT);
    
    if(tCount > 5)
    {
        CPrintToChat(client, "{green}[BRush]{default} В данный момент идет выбор напарника, ожидайте.");
        CloseHandle(menu);
        return;
    }
    
    if(ctCount < 3)
        AddMenuItem(menu, "ct", "Зайти за CT");
    if(tCount < 5)
        AddMenuItem(menu, "t", "Зайти за T");
        
    SetMenuExitButton(menu, false);
    DisplayMenu(menu, client, 10);
    
    g_bWaitingForSlot[client] = true;
    
    if(g_hSlotMenuTimers[client] != INVALID_HANDLE)
    {
        KillTimer(g_hSlotMenuTimers[client]);
    }
    g_hSlotMenuTimers[client] = CreateTimer(10.0, Timer_KickAFKSpectator, GetClientUserId(client));
}



public Action:Timer_KickAFKSpectator(Handle:timer, any:userid)
{
    new client = GetClientOfUserId(userid);
    
    if(client && IsClientInGame(client) && 
       GetClientTeam(client) == CS_TEAM_SPECTATOR && 
       g_bWaitingForSlot[client])
    {
        KickClient(client, "AFK - Не выбрал команду вовремя");
    }
    
    g_hSlotMenuTimers[client] = INVALID_HANDLE;
    g_bWaitingForSlot[client] = false;
    
    return Plugin_Stop;
}


public MenuHandler_SlotAvailable(Handle:menu, MenuAction:action, param1, param2)
{
    if(action == MenuAction_Select)
    {
        if(g_hSlotMenuTimers[param1] != INVALID_HANDLE)
        {
            KillTimer(g_hSlotMenuTimers[param1]);
            g_hSlotMenuTimers[param1] = INVALID_HANDLE;
        }
        g_bWaitingForSlot[param1] = false;
        
        decl String:info[32];
        GetMenuItem(menu, param2, info, sizeof(info));
        
        new tCount = GetTeamClientCount(CS_TEAM_T);
        new ctCount = GetTeamClientCount(CS_TEAM_CT);
        
        if(StrEqual(info, "ct") && ctCount < 3)
        {
            SwitchPlayerTeam(param1, CS_TEAM_CT);
            CPrintToChatAll("{green}[BRush]{default} %N присоединился к CT", param1);
        }
        else if(StrEqual(info, "t") && tCount < 5)
        {
            SwitchPlayerTeam(param1, CS_TEAM_T);
            CPrintToChatAll("{green}[BRush]{default} %N присоединился к T", param1);
        }
        else
        {
            CPrintToChat(param1, "{green}[BRush]{default} Слот уже занят");
        }
    }
    else if(action == MenuAction_End)
    {
        CloseHandle(menu);
    }
}

public OnClientConnected(client)
{
	if (!Enabled)
	{
		return 0;
	}
	if (GetClientCount(true) < 3)
	{
		GetBomsitesIndexes();
	}
	CTImmune[client] = 0;
	PlayerSwitchable[client] = 0;
	PlayerKilledCT[client] = 0;
	SwitchingPlayer[client] = 0;
	return 0;
}

public OnClientPostAdminCheck(client)
{
	new var1;
	if (!Enabled || IsFakeClient(client))
	{
		return 0;
	}
	if (ManageBots)
	{
		new humans = Client_GetCount(true, false);
		if (bot_quota + humans >= 8)
		{
			bot_quota -= 1;
			SetConVarInt(brush_botquota, bot_quota, false, false);
		}
	}
	return 0;
}

public Action:Command_JoinTeam(client, String:command[], argc)
{
	new var1;
	if (!client || !IsClientInGame(client) || SwitchingPlayer[client])
	{
		return Action:0;
	}
	decl String:TeamNum[4];
	TeamNum[0] = MissingTAG:0;
	GetCmdArg(1, TeamNum, 2);
	new team = StringToInt(TeamNum, 10);
	new tCount;
	new ctCount;
	Team_GetClientCounts(tCount, ctCount, 0);
	new var2;
	if ((team == 2 && tCount >= 5) || (team == 3 && ctCount >= 3))
	{
		SwitchPlayerTeam(client, 1);
		CPrintToChat(client, "%t", "CantJoin");
		return Action:4;
	}
	return Action:0;
}

public SwitchPlayerTeam(client, team)
{
	SwitchingPlayer[client] = 1;
	if (team > 1)
	{
		CS_SwitchTeam(client, team);
		set_random_model(client, team);
	}
	else
	{
		ChangeClientTeam(client, team);
	}
	SwitchingPlayer[client] = 0;
	return 0;
}

public Action:Event_PlayerTeam(Handle:event, String:name[], bool:dontBroadcast)
{
	SetEventBroadcast(event, true);
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new var1;
	if (client && !IsClientInGame(client) && SwitchingPlayer[client])
	{
		return Action:0;
	}
	new team = GetEventInt(event, "team");
	new tCount;
	new ctCount;
	Team_GetClientCounts(tCount, ctCount, 0);
	new var2;
	if ((team == 2 && tCount >= 5) || (team == 3 && ctCount >= 3))
	{
		CPrintToChat(client, "%t", "CantJoin");
		ClientTimer[client] = CreateTimer(0.1, Timer_HandleTeamSwitch, client, 0);
		return Action:3;
	}
	return Action:0;
}

public Action:Timer_HandleTeamSwitch(Handle:timer, any:client)
{
	ClientTimer[client] = 0;
	if (GetTeamClientCount(3) < 3)
	{
		SwitchPlayerTeam(client, 3);
		CPrintToChat(client, "%t", "OnCT");
		return Action:3;
	}
	if (GetTeamClientCount(2) < 5)
	{
		SwitchPlayerTeam(client, 2);
		CPrintToChat(client, "%t", "OnT");
		return Action:3;
	}
	SwitchPlayerTeam(client, 1);
	CPrintToChat(client, "%t", "OnSpectate");
	return Action:0;
}
public Action Command_ForceStart(int client, int args)
{
    if(!g_bGameStarted)
    {
        g_bGameStarted = true;
        GameIsLive = true;
        CPrintToChatAll("{green}[BRush]{default} Администратор %N запустил игру!", client);
        ServerCommand("mp_restartgame 3");
        return Plugin_Handled;
    }
    
    CPrintToChat(client, "{green}[BRush]{default} Игра уже запущена!");
    return Plugin_Handled;
}

public Action Command_ForceStop(int client, int args)
{
    if(g_bGameStarted)
    {
        g_bGameStarted = false;
        GameIsLive = false;
        CPrintToChatAll("{green}[BRush]{default} Администратор %N остановил игру!", client);
        if(UseConfigs)
        {
            ServerCommand("exec brush.notlive.cfg");
        }
        return Plugin_Handled;
    }
    
    CPrintToChat(client, "{green}[BRush]{default} Игра еще не запущена!");
    return Plugin_Handled;
}



public Event_PlayerSpawn(Handle:event, String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (Enabled)
	{
		CTImmune[client] = 0;
		PlayerSwitchable[client] = 0;
		PlayerKilledCT[client] = 0;
		SwitchingPlayer[client] = 0;
		if (IsPlayerFrozen[client])
		{
			ClearTimer(p_FreezeTime[client]);
			UnFreezePlayer(client);
		}
		new team = GetClientTeam(client);
		decl String:WeaponName[80];
		WeaponName[0] = MissingTAG:0;
		new wEnt = GetPlayerWeaponSlot(client, 0);
		new var1;
		if (wEnt != -1 && wEnt > MaxClients)
		{
			GetEntityClassname(wEnt, WeaponName, 80);
			new var2;
			if (StrContains(WeaponName, "awp", false) == -1 && StrContains(WeaponName, "g3sg1", false) == -1 && StrContains(WeaponName, "sg550", false) == -1)
			{
				switch (team)
				{
					case 2:
					{
						tawpno += 1;
					}
					case 3:
					{
						ctawpno += 1;
					}
					default:
					{
					}
				}
			}
		}
	}
	return 0;
}



void FreezePlayers()
{
	
	 SetEntityMoveType(client, MOVETYPE_NONE);
    IsPlayerFrozen[client] = true;
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && IsPlayerAlive(i))
        {
            int player_team = GetClientTeam(i);
            switch(player_team)
            {
                case CS_TEAM_T:
                {
                    if(TFreezeTime > 0.0)
                    {
                        FreezePlayer(i);
                        p_FreezeTime[i] = CreateTimer(TFreezeTime, Timer_UnFreezePlayer, i);
                        CPrintToChat(i, "%t", "Frozen", TFreezeTime);
                    }
                }
                case CS_TEAM_CT:
                {
                    if(CTFreezeTime > 0.0)
                    {
                        FreezePlayer(i);
                        p_FreezeTime[i] = CreateTimer(CTFreezeTime, Timer_UnFreezePlayer, i);
                        CPrintToChat(i, "%t", "Frozen", CTFreezeTime);
                    }
                }
            }
        }
    }
}

void RemoveBombSites()
{
    int ent = -1;
    while((ent = FindEntityByClassname(ent, "func_bomb_target")) != -1)
    {
        AcceptEntityInput(ent, "Kill");
    }
    
    ent = -1;
    while((ent = FindEntityByClassname(ent, "info_bomb_target")) != -1)
    {
        AcceptEntityInput(ent, "Kill");
    }
}

public void Event_RoundFreezeEnd(Handle event, const char[] name, bool dontBroadcast)
{
    if(g_bGameStarted)
    {
        GameIsLive = true;
        FreezePlayers();
        return;
    }

    if(GetTeamClientCount(CS_TEAM_T) == 5 && GetTeamClientCount(CS_TEAM_CT) == 3)
    {
        g_bGameStarted = true;
        GameIsLive = true;
        CPrintToChatAll("{green}[BRush]{default} Раунд начался!");
        FreezePlayers();
    }
    else if(!g_bGameStarted)
    {
        GameIsLive = false;
        CPrintToChatAll("{green}[BRush]{default} Ожидание игроков...");
        if(!LiveTimer)
        {
            LiveTimer = CreateTimer(3.0, CheckLive, _, TIMER_REPEAT);
        }
    }
    
    CTKiller = 0;
    numSwitched = 0;
    killers = 0;
}

public OnEntityCreated(entity, String:classname[])
{
	if (StrEqual(classname, "weapon_c4", true))
	{
		the_bomb = entity;
	}
	if (StrEqual(classname, "planted_c4", true))
	{
		the_bomb = -1;
	}
	return 0;
}

public Action:CheckLive(Handle:timer)
{
	new var1;
	if (GetTeamClientCount(2) == 5 && GetTeamClientCount(3) == 3)
	{
		LiveTimer = MissingTAG:0;
		GameIsLive = true;
		if (UseConfigs)
		{
			ServerCommand("exec brush.live.cfg");
		}
		new times;
		while (times < 3)
		{
			CPrintToChatAll("%t", "RoundGoingLive");
			times++;
		}
		ServerCommand("mp_restartgame 3");
		CTScore = 0;
		TScore = 0;
		return Action:4;
	}
	new i = 1;
	while (i <= MaxClients)
	{
		new var2;
		if (IsClientInGame(i) && GetClientTeam(i) == 1)
		{
			PrintHintText(i, "%t\n\n%t", "Prefix2", "SpecAdvert");
		}
		i++;
	}
	return Action:0;
}

public Event_BombPickup(Handle:event, String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new var1;
	if (!client || IsFakeClient(client))
	{
		return 0;
	}
	if (StrEqual(s_bombsite, "A", false))
	{
		CPrintToChat(client, "%t", "PlantA");
		return 0;
	}
	if (StrEqual(s_bombsite, "B", false))
	{
		CPrintToChat(client, "%t", "PlantB");
		return 0;
	}
	LogMessage("ERROR WITH BOMB SITE CVAR - it's not set to A or B!!");
	return 0;
}

public Event_BeginBombPlant(Handle:event, String:name[], bool:dontBroadcast)
{
	if (!GameIsLive)
	{
		return 0;
	}
	new bombsite = GetEventInt(event, "site");
	new var1;
	if ((StrEqual(s_bombsite, "B", false) && g_BombsiteB == bombsite) || (StrEqual(s_bombsite, "A", false) && g_BombsiteA == bombsite))
	{
		return 0;
	}
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new var4;
	if (StrEqual(s_bombsite, "B", false) && g_BombsiteB != bombsite)
	{
		CPrintToChat(client, "%t %t", "Prefix", "PlantB");
	}
	new var5;
	if (StrEqual(s_bombsite, "A", false) && g_BombsiteA != bombsite)
	{
		CPrintToChat(client, "%t %t", "Prefix", "PlantA");
	}
	EmitSoundToClient(client, "buttons/weapon_cant_buy.wav", -2, 0, 75, 0, 1.0, 100, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
	new c4ent = GetPlayerWeaponSlot(client, 4);
	if (c4ent != -1)
	{
		CS_DropWeapon(client, c4ent, true, false);
	}
	return 0;
}

public Event_PlayerDeath(Handle:event, String:name[], bool:dontBroadcast)
{
	if (!GameIsLive)
	{
		return 0;
	}
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new var1;
	if (attacker > 0 && attacker <= MaxClients)
	{
		new ateam = GetClientTeam(attacker);
		new victim = GetClientOfUserId(GetEventInt(event, "userid"));
		new vteam = GetClientTeam(victim);
		new var2;
		if (ateam == 2 && vteam != ateam && victim != attacker)
		{
			PlayerKilledCT[attacker]++;
			PlayerSwitchable[victim] = 1;
			CPrintToChat(victim, "%t", "CTKilled", attacker);
			if (PlayerKilledCT[attacker] == 1)
			{
				CPrintToChat(attacker, "%t", "KilledCT", victim);
				killers += 1;
				PlayerSwitchable[attacker] = 1;
				CTImmune[attacker] = 1;
			}
			if (PlayerKilledCT[attacker] >= 2)
			{
				CTKiller = GetClientUserId(attacker);
			}
		}
	}
	return 0;
}

public Event_BombExploded(Handle:event, String:name[], bool:dontBroadcast)
{
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);
	if (client)
	{
		PlayerKilledCT[client]++;
		if (PlayerKilledCT[client] == 1)
		{
			killers += 1;
			PlayerSwitchable[client] = 1;
			CTImmune[client] = 1;
			if (killers == 1)
			{
				CTKiller = userid;
			}
		}
		if (PlayerKilledCT[client] >= 2)
		{
			CTKiller = userid;
		}
	}
	return 0;
}

public Event_RoundEnd(Handle:event, String:name[], bool:dontBroadcast)
{
	CreateTimer(0.6, Timer_SetScore, any:0, 0);
	if (!GameIsLive)
	{
		return 0;
	}
	new winner = GetEventInt(event, "winner");
	if (winner == 2)
	{
		TScore += 1;
		CreateTimer(0.5, ProcessTeam, any:0, 0);
	}
	else
	{
		CTScore += 1;
		CPrintToChatAll("%t", "CTWon");
		if (CTScore >= 2)
		{
			CreateTimer(0.3, Announcement, any:0, 0);
		}
	}
	tawpno = 0;
	ctawpno = 0;
	return 0;
}

public Action:Timer_SetScore(Handle:timer)
{
	if (GameIsLive)
	{
		SetTeamScore(3, CTScore);
		SetTeamScore(2, TScore);
	}
	else
	{
		SetTeamScore(3, 700);
		SetTeamScore(2, 1337);
	}
	return Action:0;
}

public Action:Announcement(Handle:timer)
{
	CPrintToChatAll("%t", "CTWonAgain", CTScore);
	switch (CTScore)
	{
		case 3:
		{
			CPrintToChatAll("%t", "TTaunt3");
		}
		case 4:
		{
			CPrintToChatAll("%t", "TTaunt4");
		}
		case 5:
		{
			CPrintToChatAll("%t", "TTaunt5");
		}
		case 6:
		{
			CPrintToChatAll("%t", "TTaunt6");
		}
		case 7:
		{
			CPrintToChatAll("%t", "TTaunt7");
		}
		case 8, 9, 10, 11, 12, 13, 14, 15:
		{
			CPrintToChatAll("%t", "Scrambling");
			ScrambleTeams();
		}
		default:
		{
		}
	}
	return Action:0;
}

public Action:ProcessTeam(Handle:timer)
{
	new var1;
	if (the_bomb > MaxClients && IsValidEntity(the_bomb))
	{
		new bomb_owner = Weapon_GetOwner(the_bomb);
		if (bomb_owner != -1)
		{
			CS_DropWeapon(bomb_owner, the_bomb, false, false);
		}
	}
	new team;
	new i = 1;
	while (i <= MaxClients)
	{
		if (IsClientInGame(i))
		{
			new var2;
			if (IsPlayerAlive(i) && roundend_mode == 2)
			{
				SetEntProp(i, PropType:1, "m_takedamage", any:0, 1, 0);
				SetEntityRenderColor(i, 255, 255, 254, 165);
			}
			team = GetClientTeam(i);
			new var3;
			if (team == 3 && !CTImmune[i])
			{
				ClientTimer[i] = CreateTimer(0.2, Timer_ProcessCT, i, 0);
			}
			new var4;
			if (team == 2 && CTImmune[i])
			{
				ProcessT(i);
			}
		}
		i++;
	}
	if (numSwitched != 3)
	{
		if (numSwitched)
		{
			DisplayMenuToCTKiller();
		}
		SwitchRandom();
	}
	CTScore = 0;
	TScore = 0;
	CreateTimer(0.3, Timer_WhoWon, any:0, 0);
	return Action:0;
}

public Action:Timer_WhoWon(Handle:timer)
{
	CPrintToChatAll("%t", "TWon", killers);
	return Action:0;
}

public Action:Timer_ProcessCT(Handle:timer, any:client)
{
	if (IsClientInGame(client))
	{
		ClientTimer[client] = 0;
		CTImmune[client] = 1;
		SwitchPlayerTeam(client, 2);
	}
	return Action:0;
}

public ProcessT(client)
{
	numSwitched += 1;
	SwitchPlayerTeam(client, 3);
	new var1;
	if (IsPlayerAlive(client) && roundend_mode == 1)
	{
		SwitchingPlayer[client] = 1;
		CS_RespawnPlayer(client);
		SwitchingPlayer[client] = 0;
	}
	return 0;
}

public ScrambleTeams()
{
	new i = 1;
	while (i <= MaxClients)
	{
		if (IsClientInGame(i))
		{
			new team = GetClientTeam(i);
			if (team == 3)
			{
				SwitchPlayerTeam(i, 2);
			}
		}
		i++;
	}
	SwitchRandom();
	return 0;
}

public SwitchRandom()
{
	while (numSwitched < 3)
	{
		new i = Client_GetRandom(65536);
		if (i != -1)
		{
			CTImmune[i] = 1;
			ProcessT(i);
		}
		LogMessage("ERROR with SwitchRandom");
		return 0;
	}
	return 0;
}

public Action:CS_OnBuyCommand(client, String:weapon[])
{
	new var1;
	if (!UseWeaponRestrict || !GameIsLive || !Enabled)
	{
		return Action:0;
	}
	new var2;
	if ((StrContains(weapon, "flashbang", false) != -1 && !AllowFlashBangs) || (StrContains(weapon, "smokegrenade", false) != -1 && !AllowSmokes) || (StrContains(weapon, "hegrenade", false) != -1 && !AllowHEGrenades))
	{
		CPrintToChat(client, "%t %t", "Prefix", "NoNade");
		EmitSoundToClient(client, "buttons/weapon_cant_buy.wav", -2, 0, 75, 0, 1.0, 100, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
		return Action:3;
	}
	new var6;
	if (StrContains(weapon, "awp", false) == -1 && StrContains(weapon, "g3sg1", false) == -1 && StrContains(weapon, "sg550", false) == -1)
	{
		new team = GetClientTeam(client);
		switch (team)
		{
			case 2:
			{
				tawpno += 1;
			}
			case 3:
			{
				ctawpno += 1;
			}
			default:
			{
			}
		}
		new var7;
		if ((team == 2 && TAwps) || (team == 3 && CTAwps))
		{
			new var10;
			if ((team == 3 && ctawpno > CTAwpNumber) || (team == 2 && tawpno > TAwpNumber))
			{
				CPrintToChat(client, "%t %t", "Prefix", "NoSniper");
				EmitSoundToClient(client, "buttons/weapon_cant_buy.wav", -2, 0, 75, 0, 1.0, 100, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
				return Action:3;
			}
		}
		CPrintToChat(client, "%t %t", "Prefix", "NoSniper");
		EmitSoundToClient(client, "buttons/weapon_cant_buy.wav", -2, 0, 75, 0, 1.0, 100, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
		return Action:3;
	}
	return Action:0;
}

public OnClientDisconnect(int client)
{
    // Очищаем таймеры
    if(g_hSlotMenuTimers[client] != INVALID_HANDLE)
    {
        KillTimer(g_hSlotMenuTimers[client]);
        g_hSlotMenuTimers[client] = INVALID_HANDLE;
    }
    g_bWaitingForSlot[client] = false;

    // Если игра идет и игрок был в команде
    if(g_bGameStarted)
    {
        int team = GetClientTeam(client);
        if(team == CS_TEAM_CT || team == CS_TEAM_T)
        {
            CreateTimer(0.5, Timer_CheckForSpectators);
        }
    }
}

GetBomsitesIndexes()
{
	new index = -1;
	new Float:vecBombsiteCenterA[3] = 0.0;
	new Float:vecBombsiteCenterB[3] = 0.0;
	index = FindEntityByClassname(index, "cs_player_manager");
	if (index != -1)
	{
		GetEntPropVector(index, PropType:0, "m_bombsiteCenterA", vecBombsiteCenterA, 0);
		GetEntPropVector(index, PropType:0, "m_bombsiteCenterB", vecBombsiteCenterB, 0);
	}
	index = -1;
	while ((index = FindEntityByClassname(index, "func_bomb_target")) != -1)
	{
		new Float:vecBombsiteMin[3] = 0.0;
		new Float:vecBombsiteMax[3] = 0.0;
		GetEntPropVector(index, PropType:0, "m_vecMins", vecBombsiteMin, 0);
		GetEntPropVector(index, PropType:0, "m_vecMaxs", vecBombsiteMax, 0);
		if (IsVecBetween(vecBombsiteCenterA, vecBombsiteMin, vecBombsiteMax))
		{
			g_BombsiteA = index;
		}
		if (IsVecBetween(vecBombsiteCenterB, vecBombsiteMin, vecBombsiteMax))
		{
			g_BombsiteB = index;
		}
	}
	return 0;
}

bool:IsVecBetween(Float:vecVector[3], Float:vecMin[3], Float:vecMax[3])
{
	new var1;
	return vecMin[0] <= vecVector[0] <= vecMax[0] && vecMin[1] <= vecVector[1] <= vecMax[1] && vecMin[2] <= vecVector[2] <= vecMax[2];
}

public OnClientPostAdminCheck(client)
{
    if (!Enabled || IsFakeClient(client))
        return;
        
    // Управление ботами
    if (ManageBots)
    {
        new humans = Client_GetCount(true, false);
        if (bot_quota + humans >= 8)
        {
            bot_quota -= 1;
            SetConVarInt(brush_botquota, bot_quota, false, false);
        }
    }
    
    // Задержка для корректного подсчета игроков
    CreateTimer(0.5, Timer_AutoAssignTeam, GetClientUserId(client));
}

public Action Timer_AutoAssignTeam(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    
    if (!IsValidClient(client))
        return Plugin_Stop;
        
    // Получаем количество игроков в командах
    int tCount = GetTeamClientCount(CS_TEAM_T);
    int ctCount = GetTeamClientCount(CS_TEAM_CT);
    
    // Приоритет отдается команде CT если она не заполнена
    if (ctCount < 3)
    {
        SwitchPlayerTeam(client, CS_TEAM_CT);
        CPrintToChatAll("{green}[BRush]{default} %N был автоматически определен за CT", client);
    }
    // Затем проверяем команду T
    else if (tCount < 5)
    {
        SwitchPlayerTeam(client, CS_TEAM_T);
        CPrintToChatAll("{green}[BRush]{default} %N был автоматически определен за T", client);
    }
    // Если обе команды заполнены - в наблюдатели
    else
    {
        SwitchPlayerTeam(client, CS_TEAM_SPECTATOR);
        CPrintToChat(client, "{green}[BRush]{default} Команды заполнены. Вы были перемещены в наблюдатели.");
        
        // Показываем меню слотов если они появятся
        ShowFreeSlotMenu(client);
    }
    
    return Plugin_Stop;
}

public DisplayMenuToCTKiller()
{
	new CTclient = GetClientOfUserId(CTKiller);
	new var1;
	if (CTclient > 0 && CTclient <= MaxClients && IsClientConnected(CTclient) && !IsFakeClient(CTclient))
	{
		decl String:sMenuText[64];
		sMenuText[0] = MissingTAG:0;
		new Handle:menu = CreateMenu(MenuHandler_Teams, MenuAction:28);
		SetMenuTitle(menu, "%t", "Menu1");
		SetMenuExitButton(menu, true);
		AddTerroristsToMenu(menu);
		DisplayMenu(menu, CTclient, MenuTime);
	}
	else
	{
		SwitchRandom();
	}
	return 0;
}

public MenuHandler_Teams(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction:4)
	{
		new String:info[32];
		info[0] = MissingTAG:0;
		GetMenuItem(menu, param2, info, 32, 0, "", 0);
		new UserID = StringToInt(info, 10);
		new client = GetClientOfUserId(UserID);
		if (GetTeamClientCount(3) < 3)
		{
			SwitchPlayerTeam(client, 3);
			if (IsPlayerAlive(client))
			{
				SwitchingPlayer[client] = 1;
				CS_RespawnPlayer(client);
				SwitchingPlayer[client] = 0;
			}
			numSwitched += 1;
		}
		else
		{
			CPrintToChat(client, "%t", "TooLate");
		}
		ClientTimer[param1] = CreateTimer(0.2, Timer_MoreTs, param1, 0);
	}
	else
	{
		if (action == MenuAction:8)
		{
			SwitchRandom();
		}
		if (action == MenuAction:16)
		{
			CloseHandle(menu);
		}
	}
	return 0;
}

public Action:Timer_MoreTs(Handle:timer, any:client)
{
	ClientTimer[client] = 0;
	new TeamCount = GetTeamClientCount(3);
	if (TeamCount < 3)
	{
		decl String:sMenuText[64];
		sMenuText[0] = MissingTAG:0;
		new Handle:menu = CreateMenu(MenuHandler_Teams, MenuAction:28);
		SetMenuTitle(menu, "%t", "Menu2");
		SetMenuExitButton(menu, true);
		AddTerroristsToMenu(menu);
		DisplayMenu(menu, client, MenuTime);
	}
	return Action:0;
}

public AddTerroristsToMenu(Handle:menu)
{
	decl String:user_id[12];
	user_id[0] = MissingTAG:0;
	decl String:name[32];
	name[0] = MissingTAG:0;
	decl String:display[48];
	display[0] = MissingTAG:0;
	new i = 1;
	while (i <= MaxClients)
	{
		new var1;
		if (IsClientInGame(i) && GetClientTeam(i) == 2 && !CTImmune[i])
		{
			IntToString(GetClientUserId(i), user_id, 12);
			GetClientName(i, name, 32);
			Format(display, 47, "%s (%s)", name, user_id);
			AddMenuItem(menu, user_id, display, 0);
		}
		i++;
	}
	return 0;
}

public FreezePlayer(client)
{
    SetEntityMoveType(client, MOVETYPE_NONE);
	SetEntityRenderColor(client, 255, 0, 170, 174);
    IsPlayerFrozen[client] = true;
	return 0;
}

public UnFreezePlayer(client)
{
    SetEntityMoveType(client, MOVETYPE_WALK);
	SetEntityRenderColor(client, 255, 255, 255, 255);
    IsPlayerFrozen[client] = false;
	return 0;
}

public Action:Timer_UnFreezePlayer(Handle:timer, any:client)
{
	if (IsClientInGame(client))
	{
		p_FreezeTime[client] = 0;
		UnFreezePlayer(client);
	}
	return Action:0;
}

ClearTimer(&Handle:timer)
{
    if(timer != INVALID_HANDLE)
    {
        KillTimer(timer);
        timer = INVALID_HANDLE;
    }
}

set_random_model(client, team)
{
	new random = GetRandomInt(0, 3);
	switch (team)
	{
		case 2:
		{
			SetEntityModel(client, tmodels[random]);
		}
		case 3:
		{
			SetEntityModel(client, ctmodels[random]);
		}
		default:
		{
		}
	}
	return 0;
}

public OnVersionChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	if (!StrEqual(newVal, "19.09.2016", true))
	{
		SetConVarString(cvar, "19.09.2016", false, false);
	}
	return 0;
}

public OnUseWeaponRestrictChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	UseWeaponRestrict = GetConVarBool(cvar);
	return 0;
}

public OnHEGrenadesChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	AllowHEGrenades = GetConVarBool(cvar);
	return 0;
}

public OnFlashBangsChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	AllowFlashBangs = GetConVarBool(cvar);
	return 0;
}

public OnSmokesChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	AllowSmokes = GetConVarBool(cvar);
	return 0;
}

public OnCTAwpsChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	CTAwps = GetConVarBool(cvar);
	return 0;
}

public OnCTAwpNumberChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	CTAwpNumber = GetConVarInt(cvar);
	return 0;
}

public OnTAwpsChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	TAwps = GetConVarBool(cvar);
	return 0;
}

public OnTAwpNumberChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	TAwpNumber = GetConVarInt(cvar);
	return 0;
}

public OnFreezeTimeChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	FreezeTime = GetConVarInt(cvar);
	MenuTime = FreezeTime + 3 / 2;
	return 0;
}

public OnEnabledChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	if (StrEqual(newVal, "1", true))
	{
		HookEvent("bomb_beginplant", Event_BeginBombPlant, EventHookMode:1);
		HookEvent("player_death", Event_PlayerDeath, EventHookMode:1);
		HookEvent("round_end", Event_RoundEnd, EventHookMode:1);
		HookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode:1);
		HookEvent("player_team", Event_PlayerTeam, EventHookMode:0);
		HookEvent("bomb_exploded", Event_BombExploded, EventHookMode:0);
		HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode:1);
		HookEvent("bomb_pickup", Event_BombPickup, EventHookMode:1);
		AddCommandListener(Command_JoinTeam, "jointeam");
		Enabled = true;
	}
	else
	{
		UnhookEvent("bomb_beginplant", Event_BeginBombPlant, EventHookMode:1);
		UnhookEvent("player_death", Event_PlayerDeath, EventHookMode:1);
		UnhookEvent("round_end", Event_RoundEnd, EventHookMode:1);
		UnhookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode:1);
		UnhookEvent("player_team", Event_PlayerTeam, EventHookMode:0);
		UnhookEvent("bomb_exploded", Event_BombExploded, EventHookMode:0);
		UnhookEvent("player_spawn", Event_PlayerSpawn, EventHookMode:1);
		UnhookEvent("bomb_pickup", Event_BombPickup, EventHookMode:1);
		RemoveCommandListener(Command_JoinTeam, "jointeam");
		new i = 1;
		while (i <= MaxClients)
		{
			if (IsClientInGame(i))
			{
				CTImmune[i] = 0;
				PlayerSwitchable[i] = 0;
				PlayerKilledCT[i] = 0;
				SwitchingPlayer[i] = 0;
			}
			i++;
		}
		Enabled = false;
		ClearTimer(LiveTimer);
	}
	return 0;
}

public OnManageBotsChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	ManageBots = GetConVarBool(cvar);
	return 0;
}

public OnFillBotsChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	FillBots = GetConVarBool(cvar);
	if (FillBots)
	{
		new humans = Client_GetCount(true, false);
		SetConVarInt(brush_botquota, 8 - humans, false, false);
	}
	return 0;
}

public OnBotQuotaChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	bot_quota = GetConVarInt(cvar);
	return 0;
}

public OnUseConfigsChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	UseConfigs = GetConVarBool(cvar);
	return 0;
}

public OnCTFreezeTimeChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	CTFreezeTime = GetConVarFloat(cvar);
	return 0;
}

public OnTFreezeTimeChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	TFreezeTime = GetConVarFloat(cvar);
	return 0;
}

public OnRoundEndModeChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	roundend_mode = GetConVarInt(cvar);
	return 0;
}

public OnBombsiteChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	s_bombsite[0] = 0;
	GetConVarString(cvar, s_bombsite, 2);
	return 0;
}

Client_GetCount(bool:countInGameOnly, bool:countFakeClients)
{
	new numClients;
	new client = 1;
	while (client <= MaxClients)
	{
		if (IsClientConnected(client))
		{
			new var1;
			if (!(countInGameOnly && !IsClientInGame(client)))
			{
				new var2;
				if (!(!countFakeClients && IsFakeClient(client)))
				{
					numClients++;
				}
			}
		}
		client++;
	}
	return numClients;
}

Team_GetClientCounts(&team1, &team2, flags)
{
	new client = 1;
	while (client <= MaxClients)
	{
		if (Client_MatchesFilter(client, flags))
		{
			if (GetClientTeam(client) == 2)
			{
				new var1 = team1;
				var1++;
				team1 = var1;
			}
			else
			{
				if (GetClientTeam(client) == 3)
				{
					new var2 = team2;
					var2++;
					team2 = var2;
				}
			}
		}
		client++;
	}
	return 0;
}

Weapon_GetOwner(weapon)
{
	return GetEntPropEnt(weapon, PropType:1, "m_hOwner", 0);
}

Client_GetRandom(flags)
{
	decl clients[MaxClients];
	new num = Client_Get(clients, flags);
	if (num)
	{
		if (num == 1)
		{
			return clients[0];
		}
		new random = Math_GetRandomInt(0, num + -1);
		return clients[random];
	}
	return -1;
}

bool:Client_MatchesFilter(client, flags)
{
	new bool:isIngame;
	if (flags >= 128)
	{
		isIngame = IsClientInGame(client);
		if (isIngame)
		{
			if (flags & 512)
			{
				return false;
			}
		}
		return false;
	}
	else
	{
		if (!IsClientConnected(client))
		{
			return false;
		}
	}
	if (!flags)
	{
		return true;
	}
	if (flags & 256)
	{
		flags |= 136;
	}
	new var1;
	if (flags & 2 && !IsFakeClient(client))
	{
		return false;
	}
	new var2;
	if (flags & 4 && IsFakeClient(client))
	{
		return false;
	}
	new var3;
	if (flags & 32 && !Client_IsAdmin(client))
	{
		return false;
	}
	new var4;
	if (flags & 64 && Client_IsAdmin(client))
	{
		return false;
	}
	new var5;
	if (flags & 8 && !IsClientAuthorized(client))
	{
		return false;
	}
	new var6;
	if (flags & 16 && IsClientAuthorized(client))
	{
		return false;
	}
	if (isIngame)
	{
		new var7;
		if (flags & 1024 && !IsPlayerAlive(client))
		{
			return false;
		}
		new var8;
		if (flags & 2048 && IsPlayerAlive(client))
		{
			return false;
		}
		new var9;
		if (flags & 4096 && GetClientTeam(client) != 1)
		{
			return false;
		}
		new var10;
		if (flags & 8192 && GetClientTeam(client) == 1)
		{
			return false;
		}
		new var11;
		if (flags & 16384 && !IsClientObserver(client))
		{
			return false;
		}
		new var12;
		if (flags & 32768 && IsClientObserver(client))
		{
			return false;
		}
		new var13;
		if (flags & 65536 && GetClientTeam(client) != 2)
		{
			return false;
		}
		new var14;
		if (flags & 131072 && GetClientTeam(client) != 3)
		{
			return false;
		}
	}
	return true;
}

Client_Get(clients[], flags)
{
	new x;
	new client = 1;
	while (client <= MaxClients)
	{
		if (Client_MatchesFilter(client, flags))
		{
			x++;
			clients[x] = client;
		}
		client++;
	}
	return x;
}

Math_GetRandomInt(min, max)
{
	new random = GetURandomInt();
	if (!random)
	{
		random++;
	}
	return RoundToCeil(float(random) / float(2147483647) / float(max - min + 1)) + min + -1;
}

bool:Client_IsAdmin(client)
{
	new AdminId:adminId = GetUserAdmin(client);
	if (adminId == AdminId:-1)
	{
		return false;
	}
	return GetAdminFlag(adminId, AdminFlag:1, AdmAccessMode:1);
}

 