# `Trips.release_at/2` resolves named zones ("America/New_York"), which needs a
# time zone database. Consumers configure their own; tests supply one here so the
# library itself carries no runtime dependency on tzdata.
Calendar.put_time_zone_database(Tzdata.TimeZoneDatabase)

ExUnit.start()
