#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>

#include <tfdb>

#define PLUGIN_NAME        "[TFDB] Simple anticheat"
#define PLUGIN_AUTHOR      "Mikah"
#define PLUGIN_DESCRIPTION "Detects TF2 Dodgeball triggerbots"
#define PLUGIN_VERSION     "1.1.0"
#define PLUGIN_URL         "https://github.com/Mikah31/TFDB_subplugin"

public Plugin myinfo =
{
	name        = PLUGIN_NAME,
	author      = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version     = PLUGIN_VERSION,
	url         = PLUGIN_URL
};

ConVar g_Cvar_TriggerbotEnable;

bool  g_bLoaded;

int g_iTicksHeld       [MAXPLAYERS + 1];
int g_iTrackNext       [MAXPLAYERS + 1];
int g_iTickLastDeflect [MAXPLAYERS + 1];

public void OnPluginStart()
{
	g_Cvar_TriggerbotEnable = CreateConVar("tfdb_triggerbot", "1", "Enable/disable TFDB triggerbot detection", _, true, 0.0, true, 1.0);

	for (int i = 1; i <= MaxClients; i++)
		SetDefault(i);

	if (!TFDB_IsDodgeballEnabled()) return;

	TFDB_OnRocketsConfigExecuted();
}

public void TFDB_OnRocketsConfigExecuted()
{
	if (g_bLoaded) return;

	HookEvent("object_deflected", RocketDeflected);
	g_bLoaded = true;
}

public void OnMapEnd()
{
	if (!g_bLoaded) return;

	UnhookEvent("object_deflected", RocketDeflected);
	g_bLoaded = false;
}

public void OnClientPutInServer(int iClient)
{
	SetDefault(iClient);
}

public Action OnPlayerRunCmdPre(int iClient, int iButtons)
{
	if (IsFakeClient(iClient) || !IsPlayerAlive(iClient))
		return Plugin_Continue;
	
	if (g_Cvar_TriggerbotEnable.BoolValue)
		CheckTriggerbot(iClient, iButtons);
	
	return Plugin_Continue;
}

public void RocketDeflected(Event hEvent, char[] strEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));

	if (!IsClientInGame(iClient) || IsFakeClient(iClient))
		return;

	g_iTickLastDeflect[iClient] = GetGameTickCount();
}

void CheckTriggerbot(int iClient, int iButtons)
{
	if (iButtons & IN_ATTACK2)
	{
		g_iTicksHeld[iClient]++;
	}
	else if (g_iTicksHeld[iClient] != 0)
	{
		// Only track fresh hits
		int iTickCountSinceLastDeflect = GetGameTickCount() - g_iTickLastDeflect[iClient];

		if (g_iTicksHeld[iClient] == 1 && iTickCountSinceLastDeflect < 50)
		{
			char buffer[256], steamid[64];
			GetClientAuthId(iClient, AuthId_Steam2, steamid, sizeof(steamid));
			Format(buffer, sizeof(buffer), "[TFDB Anticheat] Triggerbot detected: %N (%s)", iClient, steamid);
			LogDetection(buffer);
		}
		g_iTicksHeld[iClient] = 0;
	}
}

void LogDetection(char[] strMessage)
{
	// Print to admins currently online
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			int flags = GetUserFlagBits(i);
			if (flags & ADMFLAG_GENERIC || flags & ADMFLAG_ROOT)
			{
				PrintToChat(i, strMessage);
			}
		}
	}

	// Log to TFDB_anticheat.txt with datetime
	Handle logFile = OpenFile("addons/sourcemod/logs/TFDB_anticheat.txt", "a");

	char date[32];
	FormatTime(date, sizeof(date), "%Y/%m/%d %I:%M:%S", GetTime());
	WriteFileLine(logFile, "%s %s", date, strMessage);

	logFile.Close();
}

void SetDefault(int iClient)
{	
	g_iTicksHeld[iClient] = 0;
	g_iTrackNext[iClient] = 0;
	g_iTickLastDeflect[iClient] = 0;
}
