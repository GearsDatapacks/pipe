import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
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
  Model(-100, -100)
}

type Msg {
  MouseMoved(x: Int, y: Int)
}

type Model {
  Model(mouse_x: Int, mouse_y: Int)
}

fn update(_model: Model, msg: Msg) -> Model {
  case msg {
    MouseMoved(x:, y:) -> Model(mouse_x: x, mouse_y: y)
  }
}

fn view(model: Model) -> element.Element(Msg) {
  let width = svg_width()
  let height = svg_height()

  let #(gradients, stations) =
    list.map_fold(generated.stations, dict.new(), station)

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

  let lines =
    list.flat_map(generated.lines, fn(line) {
      let colour = station.line_colour(line.line)

      list.flat_map(line.branches, fn(branch) {
        list.map(list.window_by_2(branch), fn(pair) {
          let #(from, to) = pair

          let x1 = int.to_string(longitude_to_x(from.longitude))
          let y1 = int.to_string(latitude_to_y(from.latitude))
          let x2 = int.to_string(longitude_to_x(to.longitude))
          let y2 = int.to_string(latitude_to_y(to.latitude))

          svg.line([
            attribute("x1", x1),
            attribute("y1", y1),
            attribute("x2", x2),
            attribute("y2", y2),
            attribute("stroke", colour),
            attribute("stroke-width", "2"),
          ])
        })
      })
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
    list.find_map(generated.stations, hovered_station_label(_, model))
  {
    Ok(label) -> list.append(children, [label])
    Error(_) -> children
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
    ],
    children,
  )
}

const station_width = 5

const margin = 10

fn hovered_station_label(
  station: Station,
  model: Model,
) -> Result(element.Element(Msg), Nil) {
  let x = longitude_to_x(station.longitude)
  let y = latitude_to_y(station.latitude)

  let x_equal = { x - margin } < model.mouse_x && { x + margin } > model.mouse_x
  let y_equal = { y - margin } < model.mouse_y && { y + margin } > model.mouse_y

  let hovering = x_equal && y_equal

  case hovering {
    False -> Error(Nil)
    True -> {
      let width = string.length(station.name) * 9
      let x = x - width / 2
      let y = y - 10
      let box_x = x - 7
      let box_y = y - 15

      let #(x, box_x) = case box_x <= 0 {
        False -> #(x, box_x)
        True -> #(8, 1)
      }

      let svg_width = svg_width()
      let #(x, box_x) = case box_x + width + 14 >= svg_width {
        False -> #(x, box_x)
        True -> #(svg_width - width - 8, svg_width - width - 15)
      }

      let #(y, box_y) = case box_y <= 0 {
        False -> #(y, box_y)
        True -> #(16, 1)
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

      Ok(svg.g([], [box, text]))
    }
  }
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

  let #(gradients, colour) = case colours {
    [] -> #(gradients, "#d0d0d0")
    [colour] -> #(gradients, colour)
    _ -> {
      case dict.get(gradients, colours) {
        Ok(name) -> #(gradients, "url(\"#" <> name <> "\")")
        Error(Nil) -> {
          let name = "gradient" <> int.to_string(dict.size(gradients))
          #(dict.insert(gradients, colours, name), "url(\"#" <> name <> "\")")
        }
      }
    }
  }

  #(
    gradients,
    svg.circle([
      attribute("cx", int.to_string(x)),
      attribute("cy", int.to_string(y)),
      attribute("r", int.to_string(station_width)),
      attribute("fill", colour),
    ]),
  )
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
