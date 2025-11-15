import gleam/float
import gleam/list
import gleam/option.{Some}
import gleam/regexp as regex
import gleam/string
import odysseus
import pipe/station
import simplifile as file

const stations_file = "stations.kml"

const generated_file = "src/pipe/generated.gleam"

// Would probably be better to actually parse the XML here, but it's easier to
// use regex
pub fn main() {
  let assert Ok(stations_contents) = file.read(stations_file)
    as "Failed to read stations file"

  let assert Ok(placemark_regex) =
    regex.compile(
      "<name>\\s*(.+) Station\\s*</name>\\s*"
        <> "<description>\\s*.+?\\s*</description>\\s*"
        <> "<Point>\\s*"
        <> "<coordinates>\\s*(-?\\d*\\.\\d*),(-?\\d*\\.\\d*),0\\s*</coordinates>\\s*"
        <> "</Point>\\s*"
        <> "<styleUrl>\\s*#(\\w+)\\s*</styleUrl>",
      regex.Options(case_insensitive: True, multi_line: True),
    )
    as "Regex failed to compile"

  let results = regex.scan(placemark_regex, stations_contents)

  let stations =
    list.filter_map(results, fn(match) {
      let assert [Some(name), Some(longitude), Some(latitude), Some(style)] =
        match.submatches

      case style {
        "tubeStyle" -> {
          let assert Ok(longitude) = normalise(longitude) |> float.parse
          let assert Ok(latitude) = normalise(latitude) |> float.parse
          Ok(station.Station(odysseus.unescape(name), longitude, latitude))
        }
        _ -> Error(Nil)
      }
    })

  let min_longitude =
    stations
    |> list.map(fn(station) { station.longitude })
    |> list.fold(1000.0, float.min)
  let max_longitude =
    stations
    |> list.map(fn(station) { station.longitude })
    |> list.fold(-1000.0, float.max)
  let min_latitude =
    stations
    |> list.map(fn(station) { station.latitude })
    |> list.fold(1000.0, float.min)
  let max_latitude =
    stations
    |> list.map(fn(station) { station.latitude })
    |> list.fold(-1000.0, float.max)

  let station_strings =
    list.map(stations, fn(station) {
      "Station(\""
      <> odysseus.unescape(station.name)
      <> "\", "
      <> float.to_string(station.longitude)
      <> ", "
      <> float.to_string(station.latitude)
      <> ")"
    })

  let file = "import pipe/station.{Station}

pub const stations = [
  " <> string.join(station_strings, ",\n  ") <> ",
]

pub const min_longitude = " <> float.to_string(min_longitude) <> "

pub const max_longitude = " <> float.to_string(max_longitude) <> "

pub const min_latitude = " <> float.to_string(min_latitude) <> "

pub const max_latitude = " <> float.to_string(max_latitude) <> "
"

  let assert Ok(Nil) = file.write(file, to: generated_file)
}

fn normalise(float: String) -> String {
  case float {
    "." <> float -> "0." <> float
    "-." <> float -> "-0." <> float
    _ -> float
  }
}
