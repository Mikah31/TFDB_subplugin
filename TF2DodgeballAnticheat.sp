#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>

#include <tfdb>

#define PLUGIN_NAME        "[TFDB] Simple anticheat"
#define PLUGIN_AUTHOR      "Mikah"
#define PLUGIN_DESCRIPTION "Detects TF2 Dodgeball triggerbots"
#define PLUGIN_VERSION     "1.2.2"
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

int g_iTicksHeld           [MAXPLAYERS + 1];
int g_iTickLastDeflect     [MAXPLAYERS + 1];
bool g_bMarked             [MAXPLAYERS + 1];

int g_iTotalDeflects       [MAXPLAYERS + 1]; // n
float g_fTickMean          [MAXPLAYERS + 1]; // 𝜇
float g_fTickStd           [MAXPLAYERS + 1]; // σ, we are most likely under estimating true value for std

int g_iTrackingId          [MAXPLAYERS + 1];


public void OnPluginStart()
{
	g_Cvar_TriggerbotEnable = CreateConVar("tfdb_triggerbot", "1", "Enable/disable TFDB triggerbot detection", _, true, 0.0, true, 1.0);

	RegConsoleCmd("sm_gaussianstats", CMDgaussianStats, "Retrieves stats for creating gaussian probability distribution.");
	RegConsoleCmd("sm_trackdeflects", CMDtrackDeflects, "Tracks ticksheld & gaussian statistics of a player in realtime.");

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

public void OnClientDisconnect(int iClient)
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

	g_iTotalDeflects[iClient] += 1;
	g_iTickLastDeflect[iClient] = GetGameTickCount();
}

void CheckTriggerbot(int iClient, int iButtons)
{	

	int iCurrentTick = GetGameTickCount();

	if (iButtons & IN_ATTACK2)
	{
		// We check when we receive next packet to see if detection was due to some kind of packet loss
		if (g_bMarked[iClient])
		{
			int iNextPacket = iCurrentTick - g_iTickLastDeflect[iClient];
			LogDetection(iClient, iNextPacket);

			g_bMarked[iClient] = false;
			g_iTickLastDeflect[iClient] = 0;
			g_iTicksHeld[iClient] = 0;
		}
		else
			g_iTicksHeld[iClient]++;
	}
	else if (g_iTicksHeld[iClient] > 0 && !g_bMarked[iClient])
	{
		int iTickCountSinceLastDeflect = (iCurrentTick - g_iTickLastDeflect[iClient]);

		// Only track after rocket has been hit, 1 airblast = 50 ticks
		if (iTickCountSinceLastDeflect > 50 || iTickCountSinceLastDeflect < 0)
		{
			g_iTickLastDeflect[iClient] = 0;
			g_iTicksHeld[iClient] = 0;
			return;
		}

		// Updating player statistics (mean & std)
		/*  
			Statistical approach should (of course) be HEAVILY taken with a grain of salt,
			we assume every deflect is independent & trust the data to be representative of mostly normal behaviour,
			we also assume that ticks held follows a gaussian distribution,
			we are likely underestimating the true value for standard deviation,
			the validity of this is all dubious, but it's still interesting!

			https://www.desmos.com/calculator/yl9pxpgc9a -> Probability calculation for gaussian distribution
		*/
		if (g_fTickMean[iClient] > 0)
		{
			g_fTickStd[iClient] = SquareRoot(((g_iTotalDeflects[iClient]-1.0)/g_iTotalDeflects[iClient])*(Pow(g_fTickStd[iClient],2.0)+(1.0/g_iTotalDeflects[iClient])*Pow(g_fTickMean[iClient]-g_iTicksHeld[iClient],2.0)));
			g_fTickMean[iClient] = (g_fTickMean[iClient]*(g_iTotalDeflects[iClient]-1.0)+g_iTicksHeld[iClient])/g_iTotalDeflects[iClient];
		}
		else // First hit, can not calculate std yet
			g_fTickMean[iClient] = (g_fTickMean[iClient]*(g_iTotalDeflects[iClient]-1.0)+g_iTicksHeld[iClient])/g_iTotalDeflects[iClient];

		// Triggerbot detection (other cheats = 1 tick Lmaobox = 2 ticks), mark client to check for when next m2 packet comes in
		if (g_iTicksHeld[iClient] <= 2)
			g_bMarked[iClient] = true;

		// Send deflect information of trackee to tracker's console
		DeflectTracker(iClient);
		
		if (!g_bMarked[iClient])
		{
			g_iTicksHeld[iClient] = 0;
			g_iTickLastDeflect[iClient] = 0;
		}
	}
}

void LogDetection(int iClient, int iNextPacketReceived)
{
	if (!IsClientInGame(iClient) || IsFakeClient(iClient))
		return;

	Handle logFile = OpenFile("addons/sourcemod/logs/TFDB_anticheat.txt", "a");

	char buffer[512], steamid[64], date[32];

	FormatTime(date, sizeof(date), "%Y/%m/%d %I:%M:%S", GetTime());
	GetClientAuthId(iClient, AuthId_Steam2, steamid, sizeof(steamid));
	Format(buffer, sizeof(buffer), "%s %N (%s): u=%.2f, s=%.2f, total_hits=%d, ticksheld=%d, next_packet=%d", date, iClient, steamid, g_fTickMean[iClient], g_fTickStd[iClient], g_iTotalDeflects[iClient], g_iTicksHeld[iClient], iNextPacketReceived);
	
	WriteFileLine(logFile, buffer);

	logFile.Close();
}

// Outputs to tracker's console when tracked client deflects
void DeflectTracker(int iTrackedClient)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{	
			if (g_iTrackingId[i] == iTrackedClient && g_iTrackingId[i] != 0)
			{
				char buffer[128];
				Format(buffer, sizeof(buffer), "%N: last_hit=%d, u=%.2f, s=%.2f, N=%d", iTrackedClient, g_iTicksHeld[iTrackedClient], g_fTickMean[iTrackedClient], g_fTickStd[iTrackedClient], g_iTotalDeflects[iTrackedClient]);
				PrintToConsole(i, buffer);
			}
		}
	}
}

// Gives player stats to create gaussian distribution (https://www.desmos.com/calculator/yl9pxpgc9a)
public Action CMDgaussianStats(int iClient, int iArgs)
{
	char buffer[2048];
	// Retrieving data from all clients
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			char buffer2[128];
			Format(buffer2, sizeof(buffer2), "%N: u=%.2f, s=%.2f, N=%d\n", i, g_fTickMean[i], g_fTickStd[i], g_iTotalDeflects[i]);
			StrCat(buffer, sizeof(buffer), buffer2);
		}
	}

	ReplyToCommand(iClient, buffer);

	return Plugin_Handled;
}

// Set 1 player to be tracked via clientID, outputs to tracker's console when rocket deflected
public Action CMDtrackDeflects(int iClient, int iArgs)
{

	if (iArgs > 0)
	{
		// Selected client Id
		int i = GetCmdArgInt(1);

		// Throws error in server console if we try IsClientInGame(0)
		if (!i)
		{
			g_iTrackingId[iClient] = 0;
			ReplyToCommand(iClient, "Stopped tracking");
			return Plugin_Handled;
		}

		// Set tracked client
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			g_iTrackingId[iClient] = i;
			ReplyToCommand(iClient, "Tracking: %N", i);
		}
		else
		{
			g_iTrackingId[iClient] = 0;
			ReplyToCommand(iClient, "Target is not valid, stopped tracking");
		}
			
		return Plugin_Handled;
	}

	// Command options when argument is not given
	char buffer[512] = "[0] Stop tracking\n";

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			char buffer2[64];
			Format(buffer2, sizeof(buffer2), "[%d] %N\n", i, i);
			StrCat(buffer, sizeof(buffer), buffer2);
		}
	}

	ReplyToCommand(iClient, buffer);

	return Plugin_Handled;
}

void SetDefault(int iClient)
{	
	g_iTicksHeld[iClient] = 0;
	g_iTickLastDeflect[iClient] = 0;
	g_bMarked[iClient] = false;

	g_iTotalDeflects[iClient] = 0;
	g_fTickMean[iClient] = 0.0;
	g_fTickStd[iClient] = 0.0;

	g_iTrackingId[iClient] = 0;
}
