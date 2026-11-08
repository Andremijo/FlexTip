std = "lua51"
max_line_length = false
exclude_files = { "tests/" }
ignore = {
    "212/self", -- unused self argument
    "432/self", -- shadowing self in nested script handlers
}
globals = {
    "FlexTip", "FlexTipDB", "SLASH_FLEXTIP1", "SLASH_FLEXTIP2", "SlashCmdList", "StaticPopupDialogs",
    "BINDING_HEADER_FLEXTIP", "BINDING_NAME_FLEXTIP_TOGGLECOLLAPSE", "BINDING_NAME_FLEXTIP_TOGGLELOCK",
    "BINDING_NAME_FLEXTIP_OPTIONS", "FlexTip_ToggleCollapse", "FlexTip_ToggleLock", "FlexTip_ToggleOptions",
    "FlexTip_OnAddonCompartmentClick",
}
read_globals = {
    "C_AddOns", "CreateFrame", "CUSTOM_CLASS_COLORS", "Enum", "FACTION_ALLIANCE", "FACTION_BAR_COLORS",
    "FACTION_HORDE", "GameTooltip", "GetAddOnMetadata", "GetCursorPosition", "GetGuildInfo", "hooksecurefunc",
    "InCombatLockdown", "IsAltKeyDown", "IsControlKeyDown", "issecretvalue", "IsShiftKeyDown", "LEVEL", "NO",
    "PlaySound", "PVP", "RAID_CLASS_COLORS", "Settings", "SOUNDKIT", "StaticPopup_Show", "strsplit", "strtrim",
    "TARGET", "tinsert", "TooltipDataProcessor", "TOOLTIP_UNIT_LEVEL", "UIParent", "UISpecialFrames", "UnitClass",
    "UnitExists", "UnitFactionGroup", "UnitIsPlayer", "UnitIsUnit", "UnitName", "UnitReaction", "WorldFrame", "YES",
}
