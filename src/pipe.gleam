import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import lustre
import lustre/attribute.{attribute}
import lustre/element
import lustre/element/svg
import lustre/event
import pipe/generated
import pipe/station.{type Station}

pub fn main() {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

fn init(_flags) {
  Model(
    mouse_x: -100,
    mouse_y: -100,
    view_box: None,
    mouse_pressed: None,
    station: None,
  )
}

type Msg {
  MouseMoved(x: Int, y: Int)
  MousePressed
  MouseReleased
  UserHoveredStation(Station)
  UserLeftStation
}

type Model {
  Model(
    mouse_x: Int,
    mouse_y: Int,
    view_box: Option(ViewBox),
    mouse_pressed: Option(#(Int, Int)),
    station: Option(Station),
  )
}

type ViewBox {
  ViewBox(x: Int, y: Int, width: Int, height: Int)
}

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    MouseMoved(x:, y:) -> Model(..model, mouse_x: x, mouse_y: y)
    MousePressed ->
      Model(..model, mouse_pressed: Some(#(model.mouse_x, model.mouse_y)))
    MouseReleased -> {
      case model.mouse_pressed {
        None -> model
        Some(#(x, y)) if x == model.mouse_x && y == model.mouse_y ->
          Model(..model, mouse_pressed: None, view_box: None)
        Some(#(x, y)) -> {
          let x = int.min(x, model.mouse_x) - margin
          let y = int.min(y, model.mouse_y) - margin

          let width = int.absolute_value(x - model.mouse_x)
          let height = int.absolute_value(y - model.mouse_y)

          Model(
            ..model,
            mouse_pressed: None,
            view_box: Some(calculate_view_box(x, y, width, height)),
          )
        }
      }
    }
    UserHoveredStation(station) -> Model(..model, station: Some(station))
    UserLeftStation -> Model(..model, station: None)
  }
}

fn calculate_view_box(x: Int, y: Int, width: Int, height: Int) -> ViewBox {
  let expected_aspect_ratio =
    int.to_float(svg_width()) /. int.to_float(svg_height())

  let width_f = int.to_float(width)
  let height_f = int.to_float(height)
  let actual_aspect_ratio = width_f /. height_f

  case float.compare(actual_aspect_ratio, expected_aspect_ratio) {
    order.Eq -> ViewBox(x:, y:, width:, height:)
    // The selection is too wide, so we need to increase the height
    order.Gt -> {
      let new_height =
        float.round(height_f *. actual_aspect_ratio /. expected_aspect_ratio)

      let new_y = y - { new_height - height } / 2

      ViewBox(x:, y: new_y, width:, height: new_height)
    }
    // The selection is too tall, so we need to increase the width
    order.Lt -> {
      let new_width =
        float.round(width_f *. expected_aspect_ratio /. actual_aspect_ratio)

      let new_x = x - { new_width - width } / 2

      ViewBox(x: new_x, y:, width: new_width, height:)
    }
    // 100x50
    // 10x10
    // 2
    // 1
  }
}

fn view(model: Model) -> element.Element(Msg) {
  let width = svg_width()
  let height = svg_height()

  let #(gradients, stations) =
    list.map_fold(generated.stations, dict.new(), station)

  let line_segments =
    list.fold(generated.lines, dict.new(), fn(lines, line) {
      list.fold(line.branches, lines, fn(lines, branch) {
        list.fold(list.window_by_2(branch), lines, fn(lines, pair) {
          let colour = station.line_colour(line.line)
          let pair = order_pair(pair)
          dict.upsert(lines, pair, fn(lines) {
            case lines {
              None -> [colour]
              Some(lines) -> [colour, ..lines]
            }
          })
        })
      })
    })

  let #(gradients, lines) =
    list.map_fold(dict.to_list(line_segments), gradients, fn(gradients, pair) {
      let #(#(from, to), lines) = pair

      let x1 = int.to_string(longitude_to_x(from.longitude))
      let y1 = int.to_string(latitude_to_y(from.latitude))
      let x2 = int.to_string(longitude_to_x(to.longitude))
      let y2 = int.to_string(latitude_to_y(to.latitude))

      let #(gradients, colour) = get_colour(lines, gradients)

      #(
        gradients,
        svg.line([
          attribute("x1", x1),
          attribute("y1", y1),
          attribute("x2", x2),
          attribute("y2", y2),
          attribute("stroke", colour),
          attribute("stroke-width", "2"),
        ]),
      )
    })

  let gradients =
    gradients
    |> dict.to_list
    |> list.map(fn(pair) {
      let #(colours, name) = pair

      let percentage = 100 / list.length(colours)
      let stops =
        list.index_map(colours, fn(colour, i) {
          [
            svg.stop([
              attribute("offset", int.to_string(percentage * i) <> "%"),
              attribute.styles([#("stop-color", colour)]),
            ]),
            svg.stop([
              attribute("offset", int.to_string(percentage * { i + 1 }) <> "%"),
              attribute.styles([#("stop-color", colour)]),
            ]),
          ]
        })
        |> list.flatten

      svg.linear_gradient([attribute.id(name)], stops)
    })

  let children = [
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
    ..list.flatten([gradients, lines, stations])
  ]

  let children = case
    list.filter_map(generated.stations, hovered_station_label(_, model))
  {
    [] -> children
    [label, ..labels] -> {
      let label =
        list.fold(labels, label, fn(a, b) {
          case a.1 <. b.1 {
            True -> a
            False -> b
          }
        }).0
      list.append(children, [label])
    }
  }

  let view_box = case model.view_box {
    None -> []
    Some(ViewBox(x:, y:, width:, height:)) -> {
      [
        attribute(
          "viewBox",
          int.to_string(x)
            <> " "
            <> int.to_string(y)
            <> " "
            <> int.to_string(width)
            <> " "
            <> int.to_string(height),
        ),
      ]
    }
  }

  svg.svg(
    [
      attribute.width(width),
      attribute.height(height),
      event.on("mousemove", {
        use x <- decode.field("clientX", decode.int)
        use y <- decode.field("clientY", decode.int)

        decode.success(MouseMoved(x - margin, y - margin))
      }),
      event.on_mouse_down(MousePressed),
      event.on_mouse_up(MouseReleased),
      ..view_box
    ],
    children,
  )
}

fn order_pair(
  pair: #(station.Point, station.Point),
) -> #(station.Point, station.Point) {
  case { pair.0 }.latitude <. { pair.1 }.latitude {
    True -> pair
    False -> #(pair.1, pair.0)
  }
}

const station_width = 5

const margin = 10

fn hovered_station_label(
  station: Station,
  model: Model,
) -> Result(#(element.Element(Msg), Float), Nil) {
  let x = longitude_to_x(station.longitude)
  let y = latitude_to_y(station.latitude)

  let #(mouse_x, mouse_y) = case model.view_box {
    None -> #(model.mouse_x, model.mouse_y)
    Some(ViewBox(x:, y:, width:, height:)) -> #(
      { model.mouse_x * width / svg_width() } + x,
      { model.mouse_y * height / svg_height() } + y,
    )
  }

  let assert Ok(distance) =
    int.square_root(squared(x - mouse_x) + squared(y - mouse_y))

  let hovering = distance <. int.to_float(station_width + 2)

  case hovering {
    False -> Error(Nil)
    True -> {
      let width = string.length(station.name) * 9
      let x = x - width / 2
      let y = y - 10
      let box_x = x - 7
      let box_y = y - 15

      let #(min_x, min_y, max_x) = case model.view_box {
        None -> #(0, 0, svg_width())
        Some(box) -> #(box.x, box.y, box.x + box.width)
      }
      let #(x, box_x) = case box_x <= min_x {
        False -> #(x, box_x)
        True -> #(min_x + 8, min_x + 1)
      }

      let #(x, box_x) = case box_x + width + 14 >= max_x {
        False -> #(x, box_x)
        True -> #(max_x - width - 8, max_x - width - 15)
      }

      let #(y, box_y) = case box_y <= min_y {
        False -> #(y, box_y)
        True -> #(min_y + 16, min_y + 1)
      }

      let text =
        svg.text(
          [
            attribute("x", int.to_string(x)),
            attribute("y", int.to_string(y)),
            attribute("textLength", int.to_string(width)),
          ],
          station.name,
        )

      let box =
        svg.rect([
          attribute("x", int.to_string(box_x)),
          attribute("y", int.to_string(box_y)),
          attribute("fill", "white"),
          attribute.height(20),
          attribute.width(width + 14),
          attribute("stroke-width", "2"),
          attribute("stroke", "black"),
        ])

      Ok(#(svg.g([], [box, text]), distance))
    }
  }
}

fn squared(x: Int) -> Int {
  x * x
}

fn station(
  gradients: Dict(List(String), String),
  station: Station,
) -> #(Dict(List(String), String), element.Element(Msg)) {
  let x = longitude_to_x(station.longitude)
  let y = latitude_to_y(station.latitude)

  let colours =
    station.lines
    |> list.map(station.line_colour)

  let #(gradients, colour) = get_colour(colours, gradients)

  #(
    gradients,
    svg.circle([
      attribute("cx", int.to_string(x)),
      attribute("cy", int.to_string(y)),
      attribute("r", int.to_string(station_width)),
      attribute("fill", colour),
      event.on_mouse_enter(UserHoveredStation(station)),
      event.on_mouse_out(UserLeftStation),
    ]),
  )
}

fn get_colour(
  colours: List(String),
  gradients: Dict(List(String), String),
) -> #(Dict(List(String), String), String) {
  let colours = list.sort(colours, string.compare)

  let #(gradients, colour) = case colours {
    [] -> #(gradients, "#d0d0d0")
    [colour] -> #(gradients, colour)
    _ ->
      case dict.get(gradients, colours) {
        Ok(name) -> #(gradients, "url(\"#" <> name <> "\")")
        Error(Nil) -> {
          let name = "gradient" <> int.to_string(dict.size(gradients))
          #(dict.insert(gradients, colours, name), "url(\"#" <> name <> "\")")
        }
      }
  }
  #(gradients, colour)
}

fn longitude_to_x(longitude: Float) -> Int {
  let width = int.to_float(svg_width() - station_width * 2)
  let x =
    { longitude -. generated.min_longitude }
    *. width
    /. { generated.max_longitude -. generated.min_longitude }

  float.round(x) + station_width
}

fn latitude_to_y(latitude: Float) -> Int {
  let height = int.to_float(svg_height() - station_width * 2)
  let y =
    { latitude -. generated.min_latitude }
    *. height
    /. { generated.max_latitude -. generated.min_latitude }
  svg_height() - float.round(y) - station_width
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
