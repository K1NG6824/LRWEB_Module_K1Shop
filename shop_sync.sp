#pragma semicolon 1
#include <sourcemod>
#include <shop>
#include <csgo_colors>		

public Plugin myinfo =
{
	name        = "[LK] Sync site (PRIVATE)",
	author      = "K1NG",
	version     = "2.0"
};

#define SZF(%0)           	%0, sizeof(%0)
#define CID(%0)             GetClientOfUserId(%0)
#define UID(%0)             GetClientUserId(%0)

char g_sLogFile[PLATFORM_MAX_PATH];
//int  g_iServer;				 

//int db_type;

Database		g_hDatabase;

public void OnPluginStart()
{

	LoadTranslations("k1_shop.phrases");

	if (!SQL_CheckConfig("shop_sync"))
	{
		SetFailState("Нет секции 'shop_sync' в databases.cfg");
		return;
	}
	
	BuildPath(Path_SM, SZF(g_sLogFile), "logs/shop_sync.log");
	//char sBuffer[PLATFORM_MAX_PATH];
	//KeyValues kv_settings = new KeyValues("Settings");
	
	//Shop_GetCfgFile(sBuffer, sizeof(sBuffer), "settings.txt");
	//kv_settings.ImportFromFile(sBuffer);
	//kv_settings.Rewind();
	//g_iServer = kv_settings.GetNum("serverid");
	//delete kv_settings;
	Database.Connect(OnDBConnect, "shop_sync");
}

public void OnDBConnect(Database hDatabase, const char[] szError, any data)
{
	if (hDatabase == null || szError[0])
	{
		SetFailState("OnDBConnect %s", szError);
		return;
	}

	g_hDatabase = hDatabase;

	char driver[16];
	DBDriver dbdriver = hDatabase.Driver;
	dbdriver.GetIdentifier(driver, sizeof(driver));
	
	if (!StrEqual(driver, "mysql", false))
	{
		SetFailState("DB_Connect: Driver \"%s\" is not supported!", driver);
		return;
	}

	DB_CreateTables();
}

void DB_CreateTables()
{
	char s_Query[512];
	FormatEx(s_Query, sizeof(s_Query), "CREATE TABLE IF NOT EXISTS `shop_player_sync` (\
							`id` int NOT NULL AUTO_INCREMENT,\
							`auth` varchar(22) NOT NULL,\
							`name` varchar(64) NOT NULL,\
							`gold` int NOT NULL DEFAULT '0',\
							`all_gold` int NOT NULL DEFAULT '0',\
							PRIMARY KEY (`id`)\
						) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4");
	g_hDatabase.Query(DB_OnPlayersTableLoad, s_Query, 1);
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i)) Shop_OnAuthorized(i);
	}
}



public void DB_OnPlayersTableLoad(Database db, DBResultSet results, const char[] error, any data)
{
	if (error[0])
	{
		LogError("DB_OnPlayersTableLoad %d: %s", data, error);
		delete g_hDatabase;
		g_hDatabase = null;
		return;
	}
}

public void Shop_OnAuthorized(int iClient)
{
	char szQuery[PLATFORM_MAX_PATH], szAuth[32];
	GetClientAuthId(iClient, AuthId_Engine, SZF(szAuth), true);
	FormatEx(SZF(szQuery), "SELECT `gold`, `id` FROM `shop_player_sync` WHERE `auth` = '%s' AND `gold` > 0 LIMIT 1;", szAuth);
	g_hDatabase.Query(SQL_Callback_SelectClient, szQuery, UID(iClient)); 
}

public void SQL_Callback_SelectClient(Database hDatabase, DBResultSet hResults, const char[] szError, any iUserID)
{
	if(szError[0]) 
	{
		LogError("SQL_Callback_SelectClient: %s", szError);
		return;
	}

	int iClient = CID(iUserID);
	if(iClient)
	{
		if(hResults.FetchRow())
		{
			int iGolds = hResults.FetchInt(0);
			int iIdAdd = hResults.FetchInt(1);
			if(iGolds)
			{
				char szQuery[PLATFORM_MAX_PATH], name[MAX_NAME_LENGTH];
				GetClientName(iClient, name, MAX_NAME_LENGTH);
				FormatEx(SZF(szQuery), "UPDATE `shop_player_sync` SET `gold` = 0 , `name` = '%s' WHERE `id` = %i;", name, iIdAdd);

				DataPack hDataPack = new DataPack();

				hDataPack.WriteCell(iIdAdd);
				hDataPack.WriteCell(UID(iClient));
				hDataPack.WriteCell(iGolds);

				g_hDatabase.Query(SQL_Callback_RemoveCredits, szQuery, hDataPack);
			}
		}
	}
}

public void SQL_Callback_RemoveCredits(Database hDatabase, DBResultSet hResults, const char[] szError, any hDP)
{
	DataPack hDataPack = view_as<DataPack>(hDP);
	hDataPack.Reset();
	int iIdAdd = hDataPack.ReadCell();

	if (hResults == null || szError[0])
	{
		delete hDataPack;
		LogError("SQL_Callback_RemoveCredits: %s", szError);
		return;
	}
	
	int iClient = CID(hDataPack.ReadCell());
	if(iClient && hResults.AffectedRows)
	{
		char szQuery[PLATFORM_MAX_PATH];
		FormatEx(SZF(szQuery), "SELECT `gold` FROM `shop_player_sync` WHERE `id` = '%i';", iIdAdd);
		g_hDatabase.Query(SQL_Callback_CheckClient, szQuery, hDataPack);
		return;
	}

	delete hDataPack;
}

public void SQL_Callback_CheckClient(Database hDatabase, DBResultSet hResults, const char[] szError, any hDP)
{
	DataPack hDataPack = view_as<DataPack>(hDP);
	hDataPack.Reset();
	if (hResults == null || szError[0])
	{
		delete hDataPack;
		LogError("SQL_Callback_CheckClient: %s", szError);
		return;
	}

	hDataPack.ReadCell();
	int iClient = CID(hDataPack.ReadCell());
	int iGolds = hDataPack.ReadCell();
	delete hDataPack;
	if(iClient && hResults.FetchRow() && hResults.FetchInt(0) == 0)
	{
		char szAuth[32];
		GetClientAuthId(iClient, AuthId_Engine, SZF(szAuth), true);
		Shop_GiveClientGold(iClient, iGolds, IGNORE_FORWARD_HOOK);
		LogToFile(g_sLogFile, "Игроку %N (%s) было добавлено %d золота", iClient, szAuth, iGolds);
		CGOPrintToChat(iClient, "%t", "SiteAddGold", iGolds);
	}
}

bool IsValidClient(int iClient)
{
    if (!(1 <= iClient <= MaxClients) || !IsClientInGame(iClient) || IsFakeClient(iClient) || IsClientSourceTV(iClient) || IsClientReplay(iClient))
        return false;
    return true;
}
