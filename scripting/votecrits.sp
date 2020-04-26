#pragma semicolon 1

#define PLUGIN_NAME "Vote Random Crits"
#define PLUGIN_AUTHOR "Shane Shame"
#define PLUGIN_DESCRIPTION "Vote to enable/disable random crits"
#define PLUGIN_SOURCE "https://github.com/shaneshame/sm_votecrits"
#define PLUGIN_VERSION "0.0.1"

#include <sourcemod>
#include <sdktools>

#undef REQUIRE_PLUGIN
#include <adminmenu>

#pragma newdecls required

#define VOTE_NO "###no###"
#define VOTE_YES "###yes###"

Menu g_hVoteMenu = null;

ConVar g_Cvar_RandomCritsVoteLimit;
ConVar g_Cvar_RandomCrits;

public Plugin myinfo =
{
  name = PLUGIN_NAME,
  author = PLUGIN_AUTHOR,
  description = PLUGIN_DESCRIPTION,
  version = PLUGIN_VERSION,
  url = PLUGIN_SOURCE
};

#define VOTE_NAME	0
#define VOTE_AUTHID	1
#define	VOTE_IP		2
char g_voteInfo[3][65];		/* Holds the target's name, authid, and IP */

TopMenu hTopMenu;

void DisplayVoteCritsMenu(int client)
{
  if (IsVoteInProgress())
  {
    ReplyToCommand(client, "[SM] %t", "Vote in Progress");
    return;
  }	
  
  if (!TestVoteDelay(client))
  {
    return;
  }
  
  LogAction(client, -1, "\"%L\" initiated a randomcrits vote.", client);
  ShowActivity2(client, "[SM] ", "%t", "phrases.votecrits.activity_message");

  g_hVoteMenu = new Menu(Handler_VoteCallback, MENU_ACTIONS_ALL);
  
  g_hVoteMenu.SetTitle(g_Cvar_RandomCrits.BoolValue
    ? "phrases.votecrits.prompt_vote_off"
    : "phrases.votecrits.prompt_vote_on"
  );
  g_hVoteMenu.AddItem(VOTE_YES, "Yes");
  g_hVoteMenu.AddItem(VOTE_NO, "No");
  g_hVoteMenu.ExitButton = true;
  g_hVoteMenu.DisplayVoteToAll(20);
}

public void AdminMenu_VoteCrits(
  TopMenu topmenu, 
  TopMenuAction action,
  TopMenuObject object_id,
  int param,
  char[] buffer,
  int maxlength
) {
  if (action == TopMenuAction_DisplayOption)
  {
    Format(buffer, maxlength, "%T", "phrases.votecrits.admin_menu_name", param);
  }
  else if (action == TopMenuAction_SelectOption)
  {
    DisplayVoteCritsMenu(param);
  }
  else if (action == TopMenuAction_DrawOption)
  {	
    /* disable this option if a vote is already running */
    buffer[0] = !IsNewVoteAllowed() ? ITEMDRAW_IGNORE : ITEMDRAW_DEFAULT;
  }
}

public Action Command_VoteCrits(int client, int args)
{
  if (args > 0)
  {
    ReplyToCommand(client, "[SM] Usage: sm_votecrits");
    return Plugin_Handled;	
  }
  
  DisplayVoteCritsMenu(client);
  
  return Plugin_Handled;
}

public void OnPluginStart()
{
  CreateConVar("sm_votecrits_version", PLUGIN_VERSION, "Vote crits version -- Do not modify", FCVAR_NOTIFY | FCVAR_DONTRECORD);

  LoadTranslations("common.phrases");
  LoadTranslations("basevotes.phrases");
  LoadTranslations("votecrits.phrases");
  
  RegAdminCmd("sm_votecrits", Command_VoteCrits, ADMFLAG_VOTE, "sm_votecrits");

  g_Cvar_RandomCritsVoteLimit = CreateConVar("sm_vote_crits", "0.60", "Percent required for successful random crits vote.", 0, true, 0.05, true, 1.0);	

  g_Cvar_RandomCrits = FindConVar("tf_weapon_criticals");

  AutoExecConfig(true);
  
  /* Account for late loading */
  TopMenu topmenu;
  if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != null))
  {
    OnAdminMenuReady(topmenu);
  }
}

public void OnAdminMenuReady(Handle aTopMenu)
{
  TopMenu topmenu = TopMenu.FromHandle(aTopMenu);

  /* Block us from being called twice */
  if (topmenu == hTopMenu)
  {
    return;
  }
  
  /* Save the Handle */
  hTopMenu = topmenu;
  
  /* Build the "Voting Commands" category */
  TopMenuObject voting_commands = hTopMenu.FindCategory(ADMINMENU_VOTINGCOMMANDS);

  if (voting_commands != INVALID_TOPMENUOBJECT)
  {
    hTopMenu.AddItem("sm_votecrits", AdminMenu_VoteCrits, voting_commands, "sm_votecrits", ADMFLAG_VOTE);
  }
}

public int Handler_VoteCallback(Menu menu, MenuAction action, int param1, int param2)
{
  if (action == MenuAction_End)
  {
    VoteMenuClose();
  }
  else if (action == MenuAction_Display)
  {
    char title[64];
    menu.GetTitle(title, sizeof(title));
    
    char buffer[255];
    Format(buffer, sizeof(buffer), "%T", title, param1, g_voteInfo[VOTE_NAME]);

    Panel panel = view_as<Panel>(param2);
    panel.SetTitle(buffer);
  }
  else if (action == MenuAction_DisplayItem)
  {
    char display[64];
    menu.GetItem(param2, "", 0, _, display, sizeof(display));
   
    if (strcmp(display, VOTE_NO) == 0 || strcmp(display, VOTE_YES) == 0)
    {
      char buffer[255];
      Format(buffer, sizeof(buffer), "%T", display, param1);

      return RedrawMenuItem(buffer);
    }
  }
  else if (action == MenuAction_VoteCancel && param1 == VoteCancel_NoVotes)
  {
    PrintToChatAll("[SM] %t", "No Votes Cast");
  }	
  else if (action == MenuAction_VoteEnd)
  {
    char item[PLATFORM_MAX_PATH], display[64];
    float percent, limit;
    int votes, totalVotes;

    GetMenuVoteInfo(param2, votes, totalVotes);
    menu.GetItem(param1, item, sizeof(item), _, display, sizeof(display));
    
    if (strcmp(item, VOTE_NO) == 0 && param1 == 1)
    {
      votes = totalVotes - votes; // Normalize vote count to be in relation to the VOTE_YES option.
    }
    
    percent = GetVotePercent(votes, totalVotes);

    limit = g_Cvar_RandomCritsVoteLimit.FloatValue;
    
    // A multi-argument vote is "always successful", but have to check if its a Yes/No vote.
    if ((strcmp(item, VOTE_YES) == 0 && FloatCompare(percent,limit) < 0 && param1 == 0) || (strcmp(item, VOTE_NO) == 0 && param1 == 1))
    {
      /* :TODO: g_voteTarget should be used here and set to -1 if not applicable.
       */
      LogAction(-1, -1, "Vote failed.");
      PrintToChatAll("[SM] %t", "Vote Failed", RoundToNearest(100.0*limit), RoundToNearest(100.0*percent), totalVotes);
    }
    else
    {
      PrintToChatAll("[SM] %t", "Vote Successful", RoundToNearest(100.0*percent), totalVotes);
      PrintToChatAll("[SM] %t", "Cvar changed", "tf_weapon_criticals", (g_Cvar_RandomCrits.BoolValue ? "0" : "1"));
      LogAction(-1, -1, "Changing randomcrits to %s due to vote.", (g_Cvar_RandomCrits.BoolValue ? "0" : "1"));
      g_Cvar_RandomCrits.BoolValue = !g_Cvar_RandomCrits.BoolValue;
    }
  }
  
  return 0;
}

void VoteMenuClose()
{
  delete g_hVoteMenu;
}

float GetVotePercent(int votes, int totalVotes)
{
  return float(votes) / float(totalVotes);
}

bool TestVoteDelay(int client)
{
  int delay = CheckVoteDelay();
   
  if (delay > 0)
  {
    if (delay > 60)
    {
      ReplyToCommand(client, "[SM] %t", "Vote Delay Minutes", (delay / 60));
    }
    else
    {
      ReplyToCommand(client, "[SM] %t", "Vote Delay Seconds", delay);
    }
    
    return false;
  }
   
  return true;
}

