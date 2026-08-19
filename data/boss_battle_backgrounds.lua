-- Encounter-aware overrides for the independent BOSS BG switch.
--
-- Rival fights deliberately do not appear here.  Oak's Lab, Route 2, Route
-- 24/25, the SS Anne, Pokemon Tower and Silph Co are ordinary location plates
-- selected by the active ARENA FILL collection.

return {
  trainers = {
    OPP_BROCK    = { map = "PEWTER_GYM",    file = "pewtergym.jpg" },
    OPP_MISTY    = { map = "CERULEAN_GYM",  file = "ceruleangym.jpg" },
    OPP_LT_SURGE = { map = "VERMILION_GYM", file = "vermiliongym.jpg" },
    OPP_ERIKA    = { map = "CELADON_GYM",   file = "celadongym.jpg" },
    OPP_KOGA     = { map = "FUCHSIA_GYM",   file = "fuchsiagym.jpg" },
    OPP_SABRINA  = { map = "SAFFRON_GYM",   file = "saffrongym.jpg" },
    OPP_BLAINE   = { map = "CINNABAR_GYM",  file = "blaine.jpg" },
    -- Giovanni has distinct Rocket Hideout, Silph executive-office and
    -- Viridian Gym plates.
    OPP_GIOVANNI = {
      SILPH_CO_11F = "silphboss.jpg",
      ROCKET_HIDEOUT_B4F = "rocketboss.jpg",
      VIRIDIAN_GYM = "viridianboss.png",
    },
  },

  rooms = {
    LORELEIS_ROOM = "lorelei.jpg",
    BRUNOS_ROOM = "bruno.jpg",
    AGATHAS_ROOM = "agatha.jpg",
    LANCES_ROOM = "lance.jpg",
    CHAMPIONS_ROOM = "champion.jpg",
    HALL_OF_FAME = "champion.jpg",
  },

  -- Species and map must both match so an ordinary party member never turns
  -- a route battle into a legendary encounter.  Mew is retained as supplied
  -- art for ROM/content mods but has no canonical Gen-1 map override.
  species = {
    ZAPDOS   = { map = "POWER_PLANT",          file = "zapdos.jpg" },
    ARTICUNO = { map = "SEAFOAM_ISLANDS_B4F", file = "articuno.jpg" },
    MOLTRES  = { map = "VICTORY_ROAD_2F",      file = "moltres.jpg" },
    MEWTWO   = { map = "CERULEAN_CAVE_B1F",    file = "mewtwo.jpg" },
  },
}
