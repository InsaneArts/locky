-- The launch film's config. The weather and sun widgets get a city by name, because Locky's screenshot mode has no
-- location (the docs' own example city). Privacy mode hides its name on the lock screen.
locky.setup({ widgets = {
  weather = { location = "Tbilisi" }, sun = { location = "Tbilisi" }, ["notebook.weather"] = { location = "Tbilisi" },
} })
