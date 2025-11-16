import gleam/float
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import pipe/station.{type Station, Station}
import simplifile as file
import xmlm

const stations_file = "stations-facilities.xml"

const generated_file = "src/pipe/generated.gleam"

pub fn main() {
  let assert Ok(stations_contents) = file.read(stations_file)
    as "Failed to read stations file"

  let input = xmlm.from_string(stations_contents)

  let assert Ok(input) = strip_dtd(input)

  let assert Ok(input) = strip_preamble(input)

  let assert Ok(stations) = parse_stations(input, [])
  let stations = list.reverse(stations)

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
      <> station.name
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

fn parse_stations(
  input: xmlm.Input,
  stations: List(Station),
) -> Result(List(Station), String) {
  case xmlm.signal(input) {
    Ok(#(xmlm.ElementStart(xmlm.Tag(xmlm.Name(_, "station"), _)), input)) ->
      case parse_station(input, 0, default_station(), True) {
        Ok(#(Some(station), input)) ->
          parse_stations(input, [station, ..stations])
        Ok(#(None, input)) -> parse_stations(input, stations)
        Error(error) -> Error(error)
      }
    Ok(#(xmlm.Data(_), input)) -> parse_stations(input, stations)
    Ok(#(xmlm.ElementEnd, _)) -> Ok(stations)
    Ok(_) -> Error("Expected opening station tag")
    Error(error) -> Error(xmlm.input_error_to_string(error))
  }
}

fn default_station() -> Station {
  Station(name: "", longitude: 0.0, latitude: 0.0)
}

fn parse_station(
  input: xmlm.Input,
  nesting: Int,
  station: Station,
  is_tube: Bool,
) -> Result(#(Option(Station), xmlm.Input), String) {
  case xmlm.signal(input) {
    Ok(#(xmlm.ElementStart(xmlm.Tag(xmlm.Name(_, "name"), _)), input))
      if nesting == 0
    -> {
      case parse_text(input) {
        Ok(#(name, input)) ->
          parse_station(input, nesting, Station(..station, name:), is_tube)
        Error(error) -> Error(error)
      }
    }

    Ok(#(xmlm.ElementStart(xmlm.Tag(xmlm.Name(_, "coordinates"), _)), input)) -> {
      case parse_text(input) {
        Ok(#(text, input)) -> {
          let assert [longitude, latitude, ..] = string.split(text, ",")

          let assert Ok(longitude) = float.parse(normalise(longitude))
          let assert Ok(latitude) = float.parse(normalise(latitude))
          parse_station(
            input,
            nesting,
            Station(..station, longitude:, latitude:),
            is_tube,
          )
        }
        Error(error) -> Error(error)
      }
    }

    Ok(#(xmlm.ElementStart(xmlm.Tag(xmlm.Name(_, "styleUrl"), _)), input)) -> {
      case parse_text(input) {
        Ok(#("#tubeStyle", input)) ->
          parse_station(input, nesting, station, is_tube)
        Ok(#(_, input)) -> parse_station(input, nesting, station, False)
        Error(error) -> Error(error)
      }
    }

    Ok(#(xmlm.ElementEnd, input)) if nesting == 0 ->
      case is_tube {
        True -> Ok(#(Some(station), input))
        False -> Ok(#(None, input))
      }
    Ok(#(xmlm.ElementEnd, input)) ->
      parse_station(input, nesting - 1, station, is_tube)
    Ok(#(xmlm.ElementStart(_), input)) ->
      parse_station(input, nesting + 1, station, is_tube)
    Ok(#(_, input)) -> parse_station(input, nesting, station, is_tube)
    Error(error) -> Error(xmlm.input_error_to_string(error))
  }
}

fn parse_text(input: xmlm.Input) -> Result(#(String, xmlm.Input), String) {
  case xmlm.signal(input) {
    Ok(#(xmlm.Data(text), input)) ->
      case xmlm.signal(input) {
        Ok(#(xmlm.ElementEnd, input)) -> Ok(#(string.trim(text), input))
        Ok(_) -> Error("Expected closing tag")
        Error(error) -> Error(xmlm.input_error_to_string(error))
      }
    Ok(_) -> Error("Expected text")
    Error(error) -> Error(xmlm.input_error_to_string(error))
  }
}

fn strip_preamble(input: xmlm.Input) -> Result(xmlm.Input, String) {
  case xmlm.signal(input) {
    Ok(#(xmlm.ElementStart(xmlm.Tag(xmlm.Name(_, "stations"), _)), input)) ->
      Ok(input)
    Ok(#(_, input)) -> strip_preamble(input)
    Error(error) -> Error(xmlm.input_error_to_string(error))
  }
}

fn strip_dtd(input: xmlm.Input) -> Result(xmlm.Input, String) {
  case xmlm.signal(input) {
    Error(e) -> Error(xmlm.input_error_to_string(e))
    Ok(#(xmlm.Dtd(_), input)) -> Ok(input)
    Ok(#(signal, _)) -> Error("Expected dtd, got " <> string.inspect(signal))
  }
}

fn normalise(float: String) -> String {
  case float {
    "." <> float -> "0." <> float
    "-." <> float -> "-0." <> float
    _ -> float
  }
}
