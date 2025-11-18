import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/fetch
import gleam/float
import gleam/http/request
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/pair
import gleam/result
import gleam/string
import pipe/station.{type Station, Station}
import simplifile as file

const generated_file = "src/pipe/generated.gleam"

type LineInfo {
  LineInfo(stations: Dict(String, Station), order: List(List(String)))
}

fn line_info(line: station.Line) -> Promise(LineInfo) {
  let name = case line {
    station.Bakerloo -> "bakerloo"
    station.Central -> "central"
    station.Circle -> "circle"
    station.District -> "district"
    station.HammersmithAndCity -> "hammersmith-city"
    station.Jubilee -> "jubilee"
    station.Metropolitan -> "metropolitan"
    station.Northern -> "northern"
    station.Piccadilly -> "piccadilly"
    station.Victoria -> "victoria"
    station.WaterlooAndCity -> "waterloo-city"
  }

  echo line

  let url = "https://api.tfl.gov.uk/line/" <> name <> "/route/sequence/outbound"

  let assert Ok(request) = request.to(url)
  use response <- promise.await(fetch.send(request))
  let assert Ok(response) = response
  use response <- promise.await(fetch.read_text_body(response))
  let assert Ok(response) = response
  assert response.status == 200

  let assert Ok(info) = json.parse(response.body, info_decoder(line))

  promise.resolve(info)
}

fn info_decoder(line: station.Line) -> decode.Decoder(LineInfo) {
  decode.at(
    ["stopPointSequences"],
    decode.list(decode.at(["stopPoint"], decode.list(stop_decoder(line)))),
  )
  |> decode.map(fn(stops) {
    let order = list.map(stops, list.map(_, pair.first))
    let stations =
      stops |> list.map(dict.from_list) |> list.fold(dict.new(), dict.merge)
    LineInfo(stations:, order:)
  })
}

fn stop_decoder(line: station.Line) -> decode.Decoder(#(String, Station)) {
  use id <- decode.field("icsId", decode.string)

  use name <- decode.field("name", decode.map(decode.string, strip_suffix))
  use longitude <- decode.field("lon", decode.float)
  use latitude <- decode.field("lat", decode.float)

  decode.success(#(id, Station(name:, longitude:, latitude:, lines: [line])))
}

fn strip_suffix(name: String) -> String {
  case string.ends_with(name, " Underground Station") {
    False -> name
    True -> string.drop_end(name, string.length(" Underground Station"))
  }
}

pub fn main() {
  use #(stations, lines) <- promise.map(collect_stations_and_lines(
    station.lines,
    dict.new(),
    dict.new(),
  ))

  let lines =
    dict.map_values(lines, fn(_, branches) {
      list.map(
        branches,
        list.filter_map(_, fn(id) {
          dict.get(stations, id)
          |> result.map(fn(station) {
            station.Point(
              longitude: station.longitude,
              latitude: station.latitude,
            )
          })
        }),
      )
    })
    |> dict.to_list

  let stations =
    list.sort(dict.values(stations), fn(a, b) { string.compare(a.name, b.name) })

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
      <> ", ["
      <> string.join(list.map(station.lines, line_to_string), ", ")
      <> "])"
    })

  let line_strings =
    list.map(lines, fn(pair) {
      let #(line, branches) = pair
      let branch_strings =
        list.map(branches, fn(branch) {
          "["
          <> string.join(
            list.map(branch, fn(point) {
              "Point("
              <> float.to_string(point.longitude)
              <> ", "
              <> float.to_string(point.latitude)
              <> ")"
            }),
            ", ",
          )
          <> "]"
        })

      "LineInfo("
      <> line_to_string(line)
      <> ", ["
      <> string.join(branch_strings, ", ")
      <> "])"
    })

  let file = "import pipe/station.{
  Bakerloo, Central, Circle, District, HammersmithAndCity, Jubilee, LineInfo,
  Metropolitan, Northern, Piccadilly, Point, Station, Victoria, WaterlooAndCity,
}

pub const stations = [
  " <> string.join(station_strings, ",\n  ") <> ",
]

pub const lines = [
  " <> string.join(line_strings, ",\n  ") <> ",
]

pub const min_longitude = " <> float.to_string(min_longitude) <> "

pub const max_longitude = " <> float.to_string(max_longitude) <> "

pub const min_latitude = " <> float.to_string(min_latitude) <> "

pub const max_latitude = " <> float.to_string(max_latitude) <> "
"

  let assert Ok(Nil) = file.write(file, to: generated_file)
}

fn collect_stations_and_lines(
  lines: List(station.Line),
  stations: Dict(String, Station),
  out: Dict(station.Line, List(List(String))),
) -> Promise(#(Dict(String, Station), Dict(station.Line, List(List(String))))) {
  case lines {
    [] -> promise.resolve(#(stations, out))
    [line, ..lines] -> {
      use info <- promise.await(line_info(line))

      let stations =
        dict.combine(stations, info.stations, fn(a, b) {
          Station(..a, lines: list.append(a.lines, b.lines))
        })

      let out = dict.insert(out, line, info.order)

      collect_stations_and_lines(lines, stations, out)
    }
  }
}

fn line_to_string(line: station.Line) -> String {
  case line {
    station.Bakerloo -> "Bakerloo"
    station.Central -> "Central"
    station.Circle -> "Circle"
    station.District -> "District"
    station.HammersmithAndCity -> "HammersmithAndCity"
    station.Jubilee -> "Jubilee"
    station.Metropolitan -> "Metropolitan"
    station.Northern -> "Northern"
    station.Piccadilly -> "Piccadilly"
    station.Victoria -> "Victoria"
    station.WaterlooAndCity -> "WaterlooAndCity"
  }
}
