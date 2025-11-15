import gleam/float
import gleam/int
import gleam/list
import lustre
import lustre/attribute.{attribute}
import lustre/element
import lustre/element/svg
import pipe/generated
import pipe/station.{type Station}

pub fn main() {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

fn init(_flags) {
  Nil
}

type Msg {
  NothingHappened
}

type Model =
  Nil

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    NothingHappened -> model
  }
}

fn view(model: Model) -> element.Element(Msg) {
  let Nil = model

  let width = svg_width()
  let height = svg_height()

  svg.svg([attribute.width(width), attribute.height(height)], [
    svg.text(
      [attribute("y", int.to_string(height - 50))],
      "Powered by TfL Open Data",
    ),
    svg.text(
      [attribute("y", int.to_string(height - 30))],
      "Contains OS data © Crown copyright and database rights 2016",
    ),
    svg.text(
      [attribute("y", int.to_string(height - 10))],
      "and Geomni UK Map data © and database rights [2019]",
    ),
    ..list.map(generated.stations, station)
  ])
}

const station_width = 5

const margin = 10

fn station(station: Station) -> element.Element(Msg) {
  let x = longitude_to_x(station.longitude)
  let y = latitude_to_y(station.latitude)

  svg.circle([
    attribute("cx", int.to_string(x)),
    attribute("cy", int.to_string(y)),
    attribute("r", int.to_string(station_width)),
    attribute("fill", "black"),
  ])
}

fn longitude_to_x(longitude: Float) -> Int {
  let width = int.to_float(svg_width() - station_width * 2)
  let x =
    { longitude -. generated.min_longitude }
    *. width
    /. { generated.max_longitude -. generated.min_longitude }
  float.round(x) + station_width + margin
}

fn latitude_to_y(latitude: Float) -> Int {
  let height = int.to_float(svg_height() - station_width * 2)
  let y =
    { latitude -. generated.min_latitude }
    *. height
    /. { generated.max_latitude -. generated.min_latitude }
  svg_height() - float.round(y) + station_width + margin
}

fn svg_width() {
  window_width() - margin * 2
}

fn svg_height() {
  window_height() - margin * 2
}

@external(javascript, "./pipe_ffi.mjs", "width")
fn window_width() -> Int

@external(javascript, "./pipe_ffi.mjs", "height")
fn window_height() -> Int
