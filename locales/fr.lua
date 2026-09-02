OpxWeather.Locale.register("fr", {
  ["weather.status"]                = "Il est {time}. Une journée dure {minutes} minutes " ..
                                      "réelles. Le ciel est {weather}.",
  ["weather.status.clockHeld"]      = "L'horloge est figée.",
  ["weather.status.scheduleHeld"]   = "Le cycle météo est figé.",
  ["weather.status.nextRoll"]       = "Prochain tirage dans {seconds}s.",
  ["weather.status.revision"]       = "Révision {revision}.",
  ["weather.status.degraded"]       = "Aucun préréglage météo utilisable n'est configuré.",

  ["weather.presets.header"]        = "préréglages météo (nom / préréglage moteur / poids / " ..
                                      "secondes) :",
  ["weather.presets.row"]           = "  {name} {preset} p={weight} {min}..{max}s  " ..
                                      "transition {transition}s",

  ["weather.usage.set"]             = "utilisation : <preset> [transitionSeconds]",
  ["weather.usage.next"]            = "utilisation : aucun argument",
  ["weather.usage.freeze"]          = "utilisation : <on|off>",
  ["weather.usage.time"]            = "utilisation : <HH:MM[:SS]>",
  ["weather.usage.timeFreeze"]      = "utilisation : <on|off>",
  ["weather.usage.dayLength"]       = "utilisation : <realMinutes>",

  ["weather.error.invalidTime"]     = "Ce n'est pas une heure valide. Utilisez HH:MM ou " ..
                                      "HH:MM:SS.",
  ["weather.error.invalidDayLength"] = "Une journée dure entre 1 minute et 7 jours.",
  ["weather.error.dayTooShort"]     = "Cette journée est trop courte pour qu'un client la suive.",
  ["weather.error.unknownPreset"]   = "Ce préréglage météo n'existe pas.",
  ["weather.error.presetHint"]      = "Ce préréglage météo n'existe pas. Lancez {command} " ..
                                      "pour voir la liste.",
  ["weather.error.invalidTransition"] = "Une transition dure entre 0 et 300 secondes.",
  ["weather.error.noPresets"]       = "Aucun préréglage météo n'est configuré.",
  ["weather.error.unknown"]         = "Cette action n'a pas abouti.",

  ["weather.help.status"]           = "Affiche l'heure et la météo synchronisées.",
  ["weather.help.presets"]          = "Liste les préréglages météo configurés.",
  ["weather.help.set"]              = "Passe à un préréglage météo.",
  ["weather.help.set.preset"]       = "sunny, rain, fog, sandstorm...",
  ["weather.help.set.seconds"]      = "durée de transition ; omettre pour celle du préréglage",
  ["weather.help.next"]             = "Tire tout de suite dans la table météo pondérée.",
  ["weather.help.freeze"]           = "Fige ou relance le cycle météo.",
  ["weather.help.time"]             = "Règle l'horloge de référence.",
  ["weather.help.time.value"]       = "sur 24 heures, par exemple 21:30",
  ["weather.help.timeFreeze"]       = "Fige ou relance l'horloge.",
  ["weather.help.dayLength"]        = "Définit la durée d'une journée en minutes réelles.",
  ["weather.help.dayLength.minutes"] = "180 correspond à la cadence du moteur",
})
