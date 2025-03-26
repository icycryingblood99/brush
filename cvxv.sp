/*
 * Plugin Name: BRush
 * Author: icycryingblood99
 * Created: 2025-03-26 19:09:04
 * Description: Custom gamemode for CSS v34 - terrorists vs counter-terrorists with team switching mechanics
 * Game: Counter-Strike: Source (v34)
 */

#include <sourcemod>
#include <sdktools>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required 

#define FREEZE_TIME_T 7.0
#define FREEZE_TIME_CT 4.0
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR "icycryingblood99"
#define PLUGIN_CREATED "2025-03-26 19:09:04"
#define MAX_TERRORISTS 5
#define MAX_CTS 3
#define CONFIG_PATH "cfg/sourcemod/brush/brush_config.cfg"
#define COLOR_DEFAULT "\x01"
#define COLOR_RED "\x02"
#define COLOR_TEAM "\x03"
#define COLOR_GREEN "\x04"
#define COLOR_YELLOW "\x05"
#define CHAT_TAG "{green}[BRush]{default}"
#define CHAT_T "{lightred}"
#define CHAT_CT "{blue}"
#define CHAT_DEFAULT "{default}"
#define MIN_PLAYERS_TO_START 8


// Глобальные переменные
bool g_bEnabled = true;
bool g_bGameStarted = false;
bool g_bWaitingForPlayers = true;
bool g_bMapEnding = false;
bool g_bSelectingTeammates = false;
bool g_bTeamsSwitched = false;
bool g_bRoundEnded = false;
bool g_bSlotMenuActive = false;
bool g_bSlotMenuShown[MAXPLAYERS + 1] = {false};

int g_iRoundsWon_CT = 0;
int g_iRoundsWon_T = 0;
int g_iConsecutiveCTWins = 0;
int g_iKillsThisRound[MAXPLAYERS + 1] = {0};
int g_iCurrentSelector = -1;
int g_iSelectionsRemaining[MAXPLAYERS + 1] = {0};

Handle g_hSlotTimer = null;

// Plugin Info
public Plugin myinfo = 
{
    name = "BRush",
    author = PLUGIN_AUTHOR,
    description = "Custom gamemode for CSS v34",
    version = PLUGIN_VERSION,
    url = ""
};

public void OnPluginStart()
{
    // Регистрируем команды
    RegAdminCmd("sm_brush_force", Command_ForceMode, ADMFLAG_RCON, "Force start/stop brush mode");
    RegAdminCmd("sm_brush_start", Command_StartGame, ADMFLAG_RCON, "Force start the game");
    RegAdminCmd("sm_brush_stop", Command_StopGame, ADMFLAG_RCON, "Force stop the game");
    
    // События
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("round_start", Event_RoundStart);
    HookEvent("player_death", OnClientDeath);
    HookEvent("player_hurt", OnPlayerHurt);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
    
    // Хуки
    AddCommandListener(Command_JoinTeam, "jointeam");
    AddCommandListener(Command_JoinTeam, "chooseteam");
    AddCommandListener(Command_BlockTeamMenu, "teammenu");
    AddCommandListener(Command_BlockTeamMenu, "showteamselect");
    
    // Создаем конфиг если его нет
    CreateDefaultConfig();
    
    // Сбрасываем все переменные
    ResetAllVariables();
}

void ResetAllVariables()
{
    g_bEnabled = true;
    g_bGameStarted = false;
    g_bWaitingForPlayers = true;
    g_bMapEnding = false;
    g_bSelectingTeammates = false;
    g_bTeamsSwitched = false;
    g_bRoundEnded = false;
    g_bSlotMenuActive = false;
    g_iCurrentSelector = -1;
    
    for(int i = 1; i <= MaxClients; i++)
    {
        g_bSlotMenuShown[i] = false;
        g_iKillsThisRound[i] = 0;
        g_iSelectionsRemaining[i] = 0;
    }
    
    if(g_hSlotTimer != null)
    {
        KillTimer(g_hSlotTimer);
        g_hSlotTimer = null;
    }
}

public void OnMapStart()
{
    g_bMapEnding = false;
    g_bGameStarted = false;
    g_bWaitingForPlayers = true;
    g_iRoundsWon_CT = 0;
    g_iRoundsWon_T = 0;
    g_iConsecutiveCTWins = 0;
    g_iCurrentSelector = -1;
    
    for(int i = 1; i <= MaxClients; i++)
    {
        g_bSlotMenuShown[i] = false;
        g_iKillsThisRound[i] = 0;
        g_iSelectionsRemaining[i] = 0;
    }
    
    // Выполняем конфиг
    ExecuteBRushConfig();
}

public void OnMapEnd()
{
    g_bMapEnding = true;
    g_bGameStarted = false;
    g_bWaitingForPlayers = true;
    g_bSlotMenuActive = false;
    
    if(g_hSlotTimer != null)
    {
        KillTimer(g_hSlotTimer);
        g_hSlotTimer = null;
    }
}

public void OnClientPutInServer(int client)
{
    if(!g_bEnabled || IsFakeClient(client))
        return;
        
    // Все новые игроки сначала идут в спектаторы
    CS_SwitchTeam(client, CS_TEAM_SPECTATOR);
    PrintColorChat(client, "%s %sВы перемещены в наблюдатели.", CHAT_TAG, CHAT_DEFAULT);
    
    CreateTimer(0.1, Timer_AutoAssignTeam, GetClientUserId(client));
}

public Action Command_BlockTeamMenu(int client, const char[] command, int args)
{
    return Plugin_Handled;
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    event.BroadcastDisabled = true;
    return Plugin_Changed;
}

public Action Command_StopGame(int targetClient, int args)
{
    if(!g_bGameStarted)
    {
        PrintColorChat(targetClient, "\x04[BRush]\x01 Game is not in progress!");
        return Plugin_Handled;
    }
    
    g_bGameStarted = false;
    g_bWaitingForPlayers = true;
    g_iRoundsWon_CT = 0;
    g_iRoundsWon_T = 0;
    g_iConsecutiveCTWins = 0;
    
    PrintColorChatAll("\x04[BRush]\x01 Game has been force stopped by admin!");
    ServerCommand("mp_restartgame 1");
    
    return Plugin_Handled;
}


public Action Timer_RespawnPlayer(Handle timer, any userId)
{
    int client = GetClientOfUserId(userId);
    if(IsValidClient(client) && GetClientTeam(client) > CS_TEAM_SPECTATOR)
    {
        CS_RespawnPlayer(client);
    }
    return Plugin_Stop;
}

public Action Timer_CheckPlayersForStart(Handle timer)
{
    int tCount = GetTeamClientCount(CS_TEAM_T);
    int ctCount = GetTeamClientCount(CS_TEAM_CT);
    int totalPlayers = tCount + ctCount;
    
    if(totalPlayers >= MIN_PLAYERS_TO_START && !g_bGameStarted)
    {
        StartGame();
    }
    return Plugin_Stop;
}


public void OnClientDisconnect(int targetClient)
{
    if(!g_bEnabled || !g_bGameStarted)
        return;
        
    int playerTeam = GetClientTeam(targetClient);
    
    if(playerTeam == CS_TEAM_T || playerTeam == CS_TEAM_CT)
    {
        CreateTimer(0.1, Timer_CheckTeamsAfterDisconnect);
    }
}

public Action Command_ForceMode(int targetClient, int args)
{
    if(!g_bEnabled)
    {
        g_bEnabled = true;
        PrintColorChatAll(" \x04[BRush]\x01 Mode has been \x04enabled\x01!");
        PrintColorChatAll(" \x04[BRush]\x01 Use !brush_start to force start the game");
    }
    else
    {
        g_bEnabled = false;
        g_bGameStarted = false;
        g_bWaitingForPlayers = true;
        PrintColorChatAll(" \x04[BRush]\x01 Mode has been \x02disabled\x01!");
    }
    
    return Plugin_Handled;
}

public Action Timer_FreezeAll(Handle timer)
{
    // Сообщение о заморозке для команд
    PrintColorChatAll(" \x04[BRush]\x01 \x07FF0000Terrorists\x01 are frozen for \x07FF0000%.0f seconds\x01!", FREEZE_TIME_T);
    PrintColorChatAll(" \x04[BRush]\x01 \x070000FFCounter-Terrorists\x01 are frozen for \x070000FF%.0f seconds\x01!", FREEZE_TIME_CT);
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i) && IsPlayerAlive(i))
        {
            SetEntityMoveType(i, MOVETYPE_NONE);
            float velocity[3] = {0.0, 0.0, 0.0};
            TeleportEntity(i, NULL_VECTOR, NULL_VECTOR, velocity);
            
            // Персональное сообщение о заморозке
            if(GetClientTeam(i) == CS_TEAM_T)
            {
                PrintColorChat(i, " \x04[BRush]\x01 Your team is frozen for \x07FF0000%.0f\x01 seconds!", FREEZE_TIME_T);
            }
            else if(GetClientTeam(i) == CS_TEAM_CT)
            {
                PrintColorChat(i, " \x04[BRush]\x01 Your team is frozen for \x070000FF%.0f\x01 seconds!", FREEZE_TIME_CT);
            }
        }
    }
    
    // Разная длительность заморозки для T и CT
    CreateTimer(FREEZE_TIME_CT, Timer_UnfreezeCT);
    CreateTimer(FREEZE_TIME_T, Timer_UnfreezeT);
    
    return Plugin_Stop;
}

public Action Timer_UnfreezeCT(Handle timer)
{
    bool anyUnfrozen = false;
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_CT)
        {
            SetEntityMoveType(i, MOVETYPE_WALK);
            PrintColorChat(i, " \x04[BRush]\x01 Your team is now \x070000FFunfrozen\x01!");
            anyUnfrozen = true;
        }
    }
    
    if(anyUnfrozen)
    {
        PrintColorChatAll(" \x04[BRush]\x01 \x070000FFCounter-Terrorists\x01 have been \x070000FFunfrozen\x01!");
    }
    
    return Plugin_Stop;
}

public Action Timer_UnfreezeT(Handle timer)
{
    bool anyUnfrozen = false;
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_T)
        {
            SetEntityMoveType(i, MOVETYPE_WALK);
            PrintColorChat(i, " \x04[BRush]\x01 Your team is now \x07FF0000unfrozen\x01!");
            anyUnfrozen = true;
        }
    }
    
    if(anyUnfrozen)
    {
        PrintColorChatAll(" \x04[BRush]\x01 \x07FF0000Terrorists\x01 have been \x07FF0000unfrozen\x01!");
    }
    
    return Plugin_Stop;
}



stock void PrintColorChat(int client, const char[] format, any ...)
{
    char buffer[254];
    VFormat(buffer, sizeof(buffer), format, 3);
    
    ProcessColors(buffer, sizeof(buffer));
    
    Handle msg = StartMessageOne("SayText2", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);
    BfWriteByte(msg, client);
    BfWriteByte(msg, true);
    BfWriteString(msg, buffer);
    EndMessage();
}

void ProcessColors(char[] message, int maxLen)
{
    ReplaceString(message, maxLen, "{default}", "\x01");
    ReplaceString(message, maxLen, "{green}", "\x04");
    ReplaceString(message, maxLen, "{lightred}", "\x02");
    ReplaceString(message, maxLen, "{blue}", "\x03");
}

stock void PrintColorChatAll(const char[] format, any ...)
{
    char buffer[254];
    VFormat(buffer, sizeof(buffer), format, 2);
    
    ProcessColors(buffer, sizeof(buffer));
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i))
        {
            Handle msg = StartMessageOne("SayText2", i, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);
            BfWriteByte(msg, i);
            BfWriteByte(msg, true);
            BfWriteString(msg, buffer);
            EndMessage();
        }
    }
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if(!g_bEnabled || !g_bGameStarted)
        return Plugin_Continue;
    
    int winner = event.GetInt("winner");
    g_bRoundEnded = true;
    
    switch(winner)
    {
        case CS_TEAM_CT:
        {
            g_iRoundsWon_CT++;
            g_iConsecutiveCTWins++;
            g_iRoundsWon_T = 0;
            
            PrintColorChatAll(" \x04[BRush]\x01 Round ended! Counter-Terrorists \x070000FFWin!");
            PrintColorChatAll(" \x04[BRush]\x01 Round Score: \x07FF0000T (%d)\x01 vs \x070000FFCT (%d)", g_iRoundsWon_T, g_iRoundsWon_CT);
            PrintColorChatAll(" \x04[BRush]\x01 CT Consecutive Wins: %d/7", g_iConsecutiveCTWins);
            
            if(g_iConsecutiveCTWins >= 7 && !g_bTeamsSwitched)
            {
                CreateTimer(0.1, Timer_SwitchTeams);
            }
        }
        case CS_TEAM_T:
        {
            g_iRoundsWon_T++;
            g_iConsecutiveCTWins = 0;
            
            // Находим T с наибольшим количеством убийств CT
            int topKiller = 0;
            int maxKills = 0;
            
            for(int i = 1; i <= MaxClients; i++)
            {
                if(IsValidClient(i) && GetClientTeam(i) == CS_TEAM_T && g_iKillsThisRound[i] > maxKills)
                {
                    maxKills = g_iKillsThisRound[i];
                    topKiller = i;
                }
            }
            
            if(topKiller > 0)
            {
                char topKillerName[MAX_NAME_LENGTH];
                GetClientName(topKiller, topKillerName, sizeof(topKillerName));
                
                switch(maxKills)
                {
                    case 1:
                    {
                        CS_SwitchTeam(topKiller, CS_TEAM_CT);
                        PrintColorChatAll(" \x04[BRush]\x01 Player \x07FF0000%s\x01 killed \x071 CT\x01 and moves to \x070000FFCounter-Terrorists!", topKillerName);
                    }
					case 2:
					{
   						CS_SwitchTeam(topKiller, CS_TEAM_CT);
    					TeleportToCTSpawn(topKiller);
    					PrintColorChatAll(" {GREEN}[BRush]{DEFAULT} Player {RED}%s{DEFAULT} killed {BLUE}2 CT{DEFAULT} and moves to {BLUE}Counter-Terrorists{DEFAULT}!", topKillerName);
    					PrintColorChatAll(" {GREEN}[BRush]{DEFAULT} %s can choose 1 teammate to join CT team!", topKillerName);
    					CreateTimer(0.5, Timer_ShowTeammateMenu, GetClientUserId(topKiller));
					}
case 3:
{
    // Переносим всех CT за T
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i) && GetClientTeam(i) == CS_TEAM_CT)
        {
            CS_SwitchTeam(i, CS_TEAM_T);
            TeleportToTSpawn(i);
            PrintColorChat(i, " {GREEN}[BRush]{DEFAULT} You have been moved to {RED}Terrorists");
        }
    }
    
    CS_SwitchTeam(topKiller, CS_TEAM_CT);
    TeleportToCTSpawn(topKiller);
    PrintColorChatAll(" {GREEN}[BRush]{DEFAULT} Player {RED}%s{DEFAULT} killed {BLUE}ALL CT{DEFAULT} and moves to {BLUE}Counter-Terrorists{DEFAULT}!", topKillerName);
    PrintColorChatAll(" {GREEN}[BRush]{DEFAULT} %s can choose 2 teammates to join CT team!", topKillerName);
    CreateTimer(0.5, Timer_ShowTeammateMenu, GetClientUserId(topKiller));
}
                }
            }
            
            PrintColorChatAll(" \x04[BRush]\x01 Round ended! Terrorists \x07FF0000Win!");
            PrintColorChatAll(" \x04[BRush]\x01 Round Score: \x07FF0000T (%d)\x01 vs \x070000FFCT (%d)", g_iRoundsWon_T, g_iRoundsWon_CT);
        }
    }
    
    CreateTimer(0.1, Timer_NewRound);
    
    return Plugin_Continue;
}

public Action Timer_NewRound(Handle timer)
{
    // Сбрасываем счетчики убийств
    for(int i = 1; i <= MaxClients; i++)
    {
        g_iKillsThisRound[i] = 0;
    }
    
    return Plugin_Stop;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    if(!g_bEnabled)
        return Plugin_Continue;
        
    if(!g_bGameStarted)
    {
        int totalPlayers = GetTeamClientCount(CS_TEAM_T) + GetTeamClientCount(CS_TEAM_CT);
        int playersNeeded = 8 - totalPlayers;
        
        if(playersNeeded > 0)
        {
            for(int i = 0; i < 3; i++) // Выводим сообщение 3 раза для заметности
            {
                CreateTimer(float(i) * 1.0, Timer_ShowWaitingMessage, playersNeeded);
            }
        }
        return Plugin_Continue;
    }
    
    g_bRoundEnded = false;
    
    // Сбрасываем счетчики убийств
    for(int i = 1; i <= MaxClients; i++)
    {
        g_iKillsThisRound[i] = 0;
    }
    
    // Замораживаем игроков
    CreateTimer(0.1, Timer_FreezeAll);
    
    return Plugin_Continue;
}

public Action Timer_ShowWaitingMessage(Handle timer, any playersNeeded)
{
    if(!g_bGameStarted)
    {
        PrintColorChatAll("%s %sЖдём ещё %d %s для начала игры...", 
            CHAT_TAG, 
            CHAT_DEFAULT, 
            playersNeeded, 
            playersNeeded == 1 ? "игрока" : "игроков"
        );
    }
    return Plugin_Stop;
}

public Action Timer_FreezeAndTeleport(Handle timer)
{
    float tSpawn[3], ctSpawn[3];
    bool foundT = false, foundCT = false;
    
    // Ищем точки спавна
    int spawnT = -1;
    int spawnCT = -1;
    
    while((spawnT = FindEntityByClassname(spawnT, "info_player_terrorist")) != -1)
    {
        GetEntPropVector(spawnT, Prop_Data, "m_vecOrigin", tSpawn);
        foundT = true;
        break;
    }
    
    while((spawnCT = FindEntityByClassname(spawnCT, "info_player_counterterrorist")) != -1)
    {
        GetEntPropVector(spawnCT, Prop_Data, "m_vecOrigin", ctSpawn);
        foundCT = true;
        break;
    }
    
    // Телепортируем и замораживаем игроков
    for(int i = 1; i <= MaxClients; i++)
    {
        if(!IsValidClient(i) || !IsPlayerAlive(i))
            continue;
            
        // Замораживаем
        SetEntityMoveType(i, MOVETYPE_NONE);
        
        // Телепортируем
        if(GetClientTeam(i) == CS_TEAM_T && foundT)
        {
            TeleportEntity(i, tSpawn, NULL_VECTOR, NULL_VECTOR);
        }
        else if(GetClientTeam(i) == CS_TEAM_CT && foundCT)
        {
            TeleportEntity(i, ctSpawn, NULL_VECTOR, NULL_VECTOR);
        }
    }
    
    // Размораживаем через 5 секунд
    CreateTimer(5.0, Timer_Unfreeze);
    
    return Plugin_Stop;
}

public Action Timer_Unfreeze(Handle timer)
{
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i) && IsPlayerAlive(i))
        {
            SetEntityMoveType(i, MOVETYPE_WALK);
        }
    }
    
    return Plugin_Stop;
}

public Action OnPlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    if(!g_bEnabled || !g_bGameStarted || g_bRoundEnded)
        return Plugin_Continue;
        
    return Plugin_Continue;
}

public void OnClientDeath(Event event, const char[] name, bool dontBroadcast)
{
    if(!g_bEnabled || !g_bGameStarted || g_bRoundEnded)
        return;
        
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));
    
    if(!IsValidClient(attacker) || !IsValidClient(victim))
        return;
        
    if(GetClientTeam(attacker) == CS_TEAM_T && GetClientTeam(victim) == CS_TEAM_CT)
    {
        g_iKillsThisRound[attacker]++;
    }
}

public Action Command_JoinTeam(int client, const char[] command, int args)
{
    if(!g_bEnabled)
        return Plugin_Continue;
        
    return Plugin_Handled;
}

public Action Command_StartGame(int targetClient, int args)
{
    if(!g_bEnabled)
    {
        PrintColorChat(targetClient, " \x04[BRush]\x01 Please enable brush mode first with !brush_force");
        return Plugin_Handled;
    }
    
    if(g_bGameStarted)
    {
        PrintColorChat(targetClient, " \x04[BRush]\x01 Game is already in progress!");
        return Plugin_Handled;
    }
    
    int tCount = GetTeamClientCount(CS_TEAM_T);
    int ctCount = GetTeamClientCount(CS_TEAM_CT);
    
    g_bGameStarted = true;
    g_bWaitingForPlayers = false;
    
    PrintColorChatAll(" \x04[BRush]\x01 Game has been force started by admin!");
    PrintColorChatAll(" \x04[BRush]\x01 Current players: \x07FF0000%d T\x01 vs \x070000FF%d CT", tCount, ctCount);
    
    CreateTimer(0.1, Timer_RestartGame);
    
    return Plugin_Handled;
}

public Action Timer_AutoAssignTeam(Handle timer, any userId)
{
    int client = GetClientOfUserId(userId);
    
    if(!IsValidClient(client) || !IsClientConnected(client) || !IsClientInGame(client))
        return Plugin_Stop;
    
    // Учитываем только живых игроков в командах
    int tCount = GetTeamClientCount(CS_TEAM_T);
    int ctCount = GetTeamClientCount(CS_TEAM_CT);
    int totalPlayers = tCount + ctCount;
    
    // Если игра идёт, оставляем в спектаторах
    if(g_bGameStarted)
    {
        CS_SwitchTeam(client, CS_TEAM_SPECTATOR);
        PrintColorChat(client, "%s %sИгра уже идёт. Вы перемещены в наблюдатели.", CHAT_TAG, CHAT_DEFAULT);
        return Plugin_Stop;
    }
    
    // Если игра ещё не началась, показываем сообщение об ожидании
    if(!g_bGameStarted)
    {
        int playersNeeded = 8 - totalPlayers;
        if(playersNeeded > 0)
        {
            PrintColorChatAll("%s %sЖдём ещё %d %s для начала игры...", 
                CHAT_TAG, 
                CHAT_DEFAULT, 
                playersNeeded, 
                playersNeeded == 1 ? "игрока" : "игроков"
            );
        }
    }
    
    // Автоматическое распределение по новой схеме
    if(totalPlayers == 0)
    {
        CS_SwitchTeam(client, CS_TEAM_T);
        PrintColorChat(client, "%s %sВы автоматически определены за %sТеррористов%s", CHAT_TAG, CHAT_DEFAULT, CHAT_T, CHAT_DEFAULT);
    }
    else if(totalPlayers == 1 && tCount == 1)
    {
        CS_SwitchTeam(client, CS_TEAM_CT);
        PrintColorChat(client, "%s %sВы автоматически определены за %sСпецназ%s", CHAT_TAG, CHAT_DEFAULT, CHAT_CT, CHAT_DEFAULT);
    }
    else if(totalPlayers == 2 && ctCount == 1)
    {
        CS_SwitchTeam(client, CS_TEAM_T);
        PrintColorChat(client, "%s %sВы автоматически определены за %sТеррористов%s", CHAT_TAG, CHAT_DEFAULT, CHAT_T, CHAT_DEFAULT);
    }
    else if(totalPlayers == 3 && tCount == 2)
    {
        CS_SwitchTeam(client, CS_TEAM_CT);
        PrintColorChat(client, "%s %sВы автоматически определены за %sСпецназ%s", CHAT_TAG, CHAT_DEFAULT, CHAT_CT, CHAT_DEFAULT);
    }
    else if(totalPlayers == 4 && ctCount == 2)
    {
        CS_SwitchTeam(client, CS_TEAM_T);
        PrintColorChat(client, "%s %sВы автоматически определены за %sТеррористов%s", CHAT_TAG, CHAT_DEFAULT, CHAT_T, CHAT_DEFAULT);
    }
    else if(totalPlayers == 5 && tCount == 3)
    {
        CS_SwitchTeam(client, CS_TEAM_T);
        PrintColorChat(client, "%s %sВы автоматически определены за %sТеррористов%s", CHAT_TAG, CHAT_DEFAULT, CHAT_T, CHAT_DEFAULT);
    }
    else if(totalPlayers == 6 && tCount == 4)
    {
        CS_SwitchTeam(client, CS_TEAM_T);
        PrintColorChat(client, "%s %sВы автоматически определены за %sТеррористов%s", CHAT_TAG, CHAT_DEFAULT, CHAT_T, CHAT_DEFAULT);
    }
    else if(totalPlayers == 7 && tCount == 5)
    {
        CS_SwitchTeam(client, CS_TEAM_CT);
        PrintColorChat(client, "%s %sВы автоматически определены за %sСпецназ%s", CHAT_TAG, CHAT_DEFAULT, CHAT_CT, CHAT_DEFAULT);
    }
    else
    {
        CS_SwitchTeam(client, CS_TEAM_SPECTATOR);
        PrintColorChat(client, "%s %sКоманды заполнены. Вы остаётесь в наблюдателях.", CHAT_TAG, CHAT_DEFAULT);
    }
    
    // Проверяем, можно ли начать игру
    if(totalPlayers + 1 >= MIN_PLAYERS_TO_START && !g_bGameStarted)
    {
        StartGame();
    }
    
    return Plugin_Stop;
}

// Дополнительно добавим функцию для проверки текущего баланса команд
bool IsTeamBalanceCorrect()
{
    int totalPlayers = GetTeamClientCount(CS_TEAM_T) + GetTeamClientCount(CS_TEAM_CT);
    int tCount = GetTeamClientCount(CS_TEAM_T);
    int ctCount = GetTeamClientCount(CS_TEAM_CT);
    
    switch(totalPlayers)
    {
        case 1: return (tCount == 1 && ctCount == 0);
        case 2: return (tCount == 1 && ctCount == 1);
        case 3: return (tCount == 2 && ctCount == 1);
        case 4: return (tCount == 2 && ctCount == 2);
        case 5: return (tCount == 3 && ctCount == 2);
        case 6: return (tCount == 4 && ctCount == 2);
        case 7: return (tCount == 5 && ctCount == 2);
        case 8: return (tCount == 5 && ctCount == 3);
    }
    
    return false;
}


void CheckTeamsForStart()
{
    if(g_bGameStarted || !g_bEnabled)
        return;
        
    int tCount = GetTeamClientCount(CS_TEAM_T);
    int ctCount = GetTeamClientCount(CS_TEAM_CT);
    
    if(tCount >= MAX_TERRORISTS && ctCount >= MAX_CTS)
    {
        PrintColorChatAll(" \x04[BRush]\x01 Teams are full!");
        PrintColorChatAll(" \x04[BRush]\x01 Current players: \x07FF0000%d T\x01 vs \x070000FF%d CT", tCount, ctCount);
        PrintColorChatAll(" \x04[BRush]\x01 Game starting in 3 seconds!");
        
        g_bGameStarted = true;
        g_bWaitingForPlayers = false;
        
        CreateTimer(0.1, Timer_RestartGame);
    }
}

public Action Timer_RestartGame(Handle timer)
{
    if(g_bGameStarted)
    {
        g_iRoundsWon_CT = 0;
        g_iRoundsWon_T = 0;
        g_iConsecutiveCTWins = 0;
        g_bTeamsSwitched = false;
        
        PrintColorChatAll(" \x04[BRush]\x01 Game starts in 3 seconds!");
        ExecuteBRushConfig();
        ServerCommand("mp_restartgame 3");
        CreateTimer(3.1, Timer_AnnounceGameLive);
    }
    
    return Plugin_Stop;
}

public Action Timer_AnnounceGameLive(Handle timer)
{
    for(int i = 0; i < 5; i++)
    {
        CreateTimer(float(i), Timer_ShowLiveMessage);
    }
    return Plugin_Stop;
}

public Action Timer_ShowLiveMessage(Handle timer, any number)
{
    PrintCenterTextAll("%d", number);
    PrintColorChatAll(" \x04[BRush]\x01 [\x02B\x02R\x02U\x02S\x02H \x02I\x02S \x02L\x02I\x02V\x02E \x02!\x02!\x02!\x01]");
    return Plugin_Stop;
}

public Action Timer_ShowTeammateMenu(Handle timer, any userId)
{
    int targetClient = GetClientOfUserId(userId);
    if(!IsValidClient(targetClient))
        return Plugin_Stop;
    
    g_iCurrentSelector = targetClient;
    g_bSelectingTeammates = true;
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i))
        {
            SetEntProp(i, Prop_Data, "m_takedamage", 0);
        }
    }
    
    TeleportToCTSpawn(targetClient);
    
    Menu menu = new Menu(TeammateSelect_Handler);
    int remainingSelections = (g_iKillsThisRound[targetClient] == 3) ? 2 : 1;
    
    menu.SetTitle("Select %d teammate%s to join CT (10 seconds):", 
        remainingSelections, 
        (remainingSelections > 1) ? "s" : "");
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i) && GetClientTeam(i) == CS_TEAM_T && i != targetClient)
        {
            char name[MAX_NAME_LENGTH], userid_str[8];
            GetClientName(i, name, sizeof(name));
            IntToString(GetClientUserId(i), userid_str, sizeof(userid_str));
            menu.AddItem(userid_str, name);
        }
    }
    
    g_iSelectionsRemaining[targetClient] = remainingSelections;
    menu.Display(targetClient, 10);
    
    CreateTimer(10.0, Timer_DisableImmunity);
    
    return Plugin_Stop;
}

public int TeammateSelect_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            char userid_str[8];
            menu.GetItem(param2, userid_str, sizeof(userid_str));
            int target = GetClientOfUserId(StringToInt(userid_str));
            
            if(IsValidClient(target))
            {
                char selectorName[MAX_NAME_LENGTH], targetName[MAX_NAME_LENGTH];
                GetClientName(param1, selectorName, sizeof(selectorName));
                GetClientName(target, targetName, sizeof(targetName));
                
                CS_SwitchTeam(target, CS_TEAM_CT);
                PrintColorChatAll(" \x0C[BRush] %s selected %s to join Counter-Terrorists!", selectorName, targetName);
            }
        }
        case MenuAction_End:
        {
            delete menu;
        }
        case MenuAction_Cancel:
        {
            if(param2 == MenuCancel_Timeout)
            {
                ArrayList tPlayers = new ArrayList();
                
                for(int i = 1; i <= MaxClients; i++)
                {
                    if(IsValidClient(i) && GetClientTeam(i) == CS_TEAM_T && i != param1)
                    {
                        tPlayers.Push(i);
                    }
                }
                
                if(tPlayers.Length > 0)
                {
                    int randomIndex = GetRandomInt(0, tPlayers.Length - 1);
                    int randomPlayer = tPlayers.Get(randomIndex);
                    
                    char selectorName[MAX_NAME_LENGTH], targetName[MAX_NAME_LENGTH];
                    GetClientName(param1, selectorName, sizeof(selectorName));
                    GetClientName(randomPlayer, targetName, sizeof(targetName));
                    
                    CS_SwitchTeam(randomPlayer, CS_TEAM_CT);
                    PrintColorChatAll(" \x04[BRush]\x01 %s didn't select in time!", selectorName);
                    PrintColorChatAll(" \x0C[BRush] Random selection: %s joins Counter-Terrorists!", targetName);
                }
                
                delete tPlayers;
            }
        }
    }
    
    return 0;
}

public Action Timer_DisableImmunity(Handle timer)
{
    g_bSelectingTeammates = false;
    g_iCurrentSelector = -1;
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i))
        {
            SetEntProp(i, Prop_Data, "m_takedamage", 2);
        }
    }
    
    PrintColorChatAll(" \x04[BRush]\x01 Team selection time has ended. \x070000FFImmunity disabled!");
    
    return Plugin_Stop;
}

public Action Timer_SwitchTeams(Handle timer)
{
    if(!g_bGameStarted)
        return Plugin_Stop;
        
    ArrayList tPlayers = new ArrayList();
    ArrayList ctPlayers = new ArrayList();
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i))
        {
            if(GetClientTeam(i) == CS_TEAM_T)
                tPlayers.Push(i);
            else if(GetClientTeam(i) == CS_TEAM_CT)
                ctPlayers.Push(i);
        }
    }
    
    // Перемешиваем массив T игроков
    for(int i = 0; i < tPlayers.Length; i++)
    {
        int r = GetRandomInt(0, tPlayers.Length - 1);
        int temp = tPlayers.Get(i);
        tPlayers.Set(i, tPlayers.Get(r));
        tPlayers.Set(r, temp);
    }
    
    // Переносим всех CT за T
    for(int i = 0; i < ctPlayers.Length; i++)
    {
        int player = ctPlayers.Get(i);
        CS_SwitchTeam(player, CS_TEAM_T);
        PrintColorChat(player, " \x04[BRush]\x01 You have been moved to \x07FF0000Terrorists");
    }
    
    // Переносим 3 случайных T за CT
    for(int i = 0; i < 3 && i < tPlayers.Length; i++)
    {
        int player = tPlayers.Get(i);
        CS_SwitchTeam(player, CS_TEAM_CT);
        PrintToChat(player, " \x04[BRush]\x01 You have been moved to \x070000FFCounter-Terrorists");
    }
    
    delete tPlayers;
    delete ctPlayers;
    
    g_bTeamsSwitched = true;
    g_iConsecutiveCTWins = 0;
    
    PrintColorChatAll(" \x04[BRush]\x01 Teams have been switched due to 7 consecutive CT wins!");
    PrintColorChatAll(" \x04[BRush]\x01 Game will continue with new teams!");
    
    ServerCommand("mp_restartgame 3");
    
    return Plugin_Stop;
}

void StartGame()
{
    if(g_bGameStarted)
        return;
        
    g_bGameStarted = true;
    g_bWaitingForPlayers = false;
    
    PrintColorChatAll("%s %sИгра начинается! Все игроки на местах!", CHAT_TAG, CHAT_DEFAULT);
    
    // Создаём таймер для показа BRUSH IS LIVE
    CreateTimer(1.0, Timer_AnnounceGameLive);
    
    // Рестарт раунда
    CreateTimer(0.1, Timer_RestartGame);
}

public Action Timer_CheckTeamsAfterDisconnect(Handle timer)
{
    int tCount = GetTeamClientCount(CS_TEAM_T);
    int ctCount = GetTeamClientCount(CS_TEAM_CT);
    
    // Если есть наблюдатели и есть свободные слоты
    if((tCount < MAX_TERRORISTS || ctCount < MAX_CTS) && HasSpectators())
    {
        // Показываем меню всем наблюдателям
        ShowSlotMenuToAllSpectators();
    }
    
    return Plugin_Stop;
}

bool HasSpectators()
{
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i) && GetClientTeam(i) == CS_TEAM_SPECTATOR)
            return true;
    }
    return false;
}

void ShowSlotMenuToAllSpectators()
{
    // Защита от повторного показа меню
    if(g_bSlotMenuActive)
        return;
        
    g_bSlotMenuActive = true;
    
    int tCount = GetTeamClientCount(CS_TEAM_T);
    int ctCount = GetTeamClientCount(CS_TEAM_CT);
    
    // Показываем меню всем наблюдателям
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i) && GetClientTeam(i) == CS_TEAM_SPECTATOR)
        {
            Menu menu = new Menu(SlotMenu_Handler);
            menu.SetTitle("Free slot available! (10 seconds to join)\nFree slots: T[%d/5] CT[%d/3]", tCount, ctCount);
            
            if(tCount < MAX_TERRORISTS)
                menu.AddItem("t", "Join Terrorists");
            if(ctCount < MAX_CTS)
                menu.AddItem("ct", "Join Counter-Terrorists");
            
            menu.ExitButton = false;
            menu.Display(i, 10);
        }
    }
    
    // Создаем таймер для кика неактивных наблюдателей
    g_hSlotTimer = CreateTimer(10.0, Timer_KickInactiveSpectators);
    
    // Оповещаем всех о свободном слоте
    PrintColorChatAll(" \x04[BRush]\x01 A player has left. Free slot available!");
    PrintColorChatAll(" \x04[BRush]\x01 Current teams: \x07FF0000T (%d/5)\x01 vs \x070000FFCT (%d/3)", tCount, ctCount);
}

public int SlotMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            char info[4];
            menu.GetItem(param2, info, sizeof(info));
            
            int tCount = GetTeamClientCount(CS_TEAM_T);
            int ctCount = GetTeamClientCount(CS_TEAM_CT);
            
            if(StrEqual(info, "t") && tCount < MAX_TERRORISTS)
            {
                CS_SwitchTeam(param1, CS_TEAM_T);
                PrintColorChatAll(" \x04[BRush]\x01 Player \x07FF0000%N\x01 joined Terrorists!", param1);
                g_bSlotMenuActive = false;
                if(g_hSlotTimer != null)
                {
                    KillTimer(g_hSlotTimer);
                    g_hSlotTimer = null;
                }
            }
            else if(StrEqual(info, "ct") && ctCount < MAX_CTS)
            {
                CS_SwitchTeam(param1, CS_TEAM_CT);
                PrintColorChatAll(" \x04[BRush]\x01 Player \x070000FF%N\x01 joined Counter-Terrorists!", param1);
                g_bSlotMenuActive = false;
                if(g_hSlotTimer != null)
                {
                    KillTimer(g_hSlotTimer);
                    g_hSlotTimer = null;
                }
            }
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }
    
    return 0;
}

public Action Timer_KickInactiveSpectators(Handle timer)
{
    g_hSlotTimer = null;
    g_bSlotMenuActive = false;
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i) && GetClientTeam(i) == CS_TEAM_SPECTATOR)
        {
            KickClient(i, "AFK - Did not join team when slot was available");
        }
    }
    
    return Plugin_Stop;
}

void TeleportToCTSpawn(int client)
{
    ArrayList spawnPoints = new ArrayList(3);
    float spawnPoint[3];
    int spawnEnt = -1;
    
    // Собираем все точки спавна
    while ((spawnEnt = FindEntityByClassname(spawnEnt, "info_player_counterterrorist")) != -1)
    {
        GetEntPropVector(spawnEnt, Prop_Data, "m_vecOrigin", spawnPoint);
        spawnPoints.PushArray(spawnPoint);
    }
    
    if(spawnPoints.Length > 0)
    {
        // Выбираем случайную точку спавна
        int randomIndex = GetRandomInt(0, spawnPoints.Length - 1);
        float teleportPoint[3];
        spawnPoints.GetArray(randomIndex, teleportPoint);
        
        // Телепортируем игрока
        TeleportEntity(client, teleportPoint, NULL_VECTOR, NULL_VECTOR);
    }
    
    delete spawnPoints;
}

void TeleportToTSpawn(int client)
{
    ArrayList spawnPoints = new ArrayList(3);
    float spawnPoint[3];
    int spawnEnt = -1;
    
    while ((spawnEnt = FindEntityByClassname(spawnEnt, "info_player_terrorist")) != -1)
    {
        GetEntPropVector(spawnEnt, Prop_Data, "m_vecOrigin", spawnPoint);
        spawnPoints.PushArray(spawnPoint);
    }
    
    if(spawnPoints.Length > 0)
    {
        int randomIndex = GetRandomInt(0, spawnPoints.Length - 1);
        float teleportPoint[3];
        spawnPoints.GetArray(randomIndex, teleportPoint);
        TeleportEntity(client, teleportPoint, NULL_VECTOR, NULL_VECTOR);
    }
    
    delete spawnPoints;
}

void CreateDefaultConfig()
{
    char configPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configPath, sizeof(configPath), "../" ... CONFIG_PATH);
    
    char dirPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, dirPath, sizeof(dirPath), "../cfg/sourcemod/brush");
    if(!DirExists(dirPath))
    {
        CreateDirectory(dirPath, 511);
    }
    
    File file = OpenFile(configPath, "w");
    if(file != null)
    {
        file.WriteLine("// BRush Configuration");
        file.WriteLine("// Created: %s", PLUGIN_CREATED);
        file.WriteLine("// Author: %s", PLUGIN_AUTHOR);
        file.WriteLine("// Game: Counter-Strike: Source (v34)");
        file.WriteLine("");
        file.WriteLine("mp_startmoney 10000");
        file.WriteLine("mp_freezetime 5");
        file.WriteLine("mp_roundtime 1");
        file.WriteLine("mp_timelimit 0");
        file.WriteLine("mp_winlimit 0");
        file.WriteLine("mp_maxrounds 0");
        file.WriteLine("mp_friendlyfire 0");
        file.WriteLine("mp_autoteambalance 0");
        file.WriteLine("mp_limitteams 0");
        file.WriteLine("sv_alltalk 1");
        
        delete file;
        PrintToServer("[BRush] Created default config: %s", CONFIG_PATH);
        LogMessage("[BRush] Created default config: %s", CONFIG_PATH);
    }
}

bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client));
}

void ExecuteBRushConfig()
{
    char configPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configPath, sizeof(configPath), "../" ... CONFIG_PATH);
    
    if(FileExists(configPath))
    {
        ServerCommand("exec sourcemod/brush/brush_config.cfg");
        PrintToServer("[BRush] Executing config: %s", CONFIG_PATH);
    }
    else
    {
        PrintToServer("[BRush] Warning: Config file not found: %s", CONFIG_PATH);
        CreateDefaultConfig();
    }
}