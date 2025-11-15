import gleam/list
import gleam/option.{Some}
import gleam/regexp as regex
import gleam/string
import odysseus
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
          Ok(
            "Station(\""
            <> odysseus.unescape(name)
            <> "\", "
            <> normalise(longitude)
            <> ", "
            <> normalise(latitude)
            <> ")",
          )
        }
        _ -> Error(Nil)
      }
    })

  let file = "import pipe/station.{Station}

pub const stations = [
  " <> string.join(stations, ",\n  ") <> ",
]
"

  let assert Ok(Nil) = file.write(file, to: generated_file)
}

fn normalise(float: String) -> String {
  case float {
    "." <> float -> "0." <> float
    "-." <> float -> "-0." <> float
    _ -> float
  }
  |> string.reverse
  |> strip_zeros
}

fn strip_zeros(float: String) -> String {
  case float {
    "0" <> float -> strip_zeros(float)
    _ -> string.reverse(float)
  }
}
