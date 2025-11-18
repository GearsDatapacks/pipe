pub type Station {
  Station(name: String, longitude: Float, latitude: Float, lines: List(Line))
}

pub type Line {
  Bakerloo
  Central
  Circle
  District
  HammersmithAndCity
  Jubilee
  Metropolitan
  Northern
  Piccadilly
  Victoria
  WaterlooAndCity
}

pub const lines = [
  Bakerloo,
  Central,
  Circle,
  District,
  HammersmithAndCity,
  Jubilee,
  Metropolitan,
  Northern,
  Piccadilly,
  Victoria,
  WaterlooAndCity,
]

pub fn line_colour(line: Line) -> String {
  case line {
    Bakerloo -> "#AE6118"
    Central -> "#E41F1F"
    Circle -> "#F8D42D"
    District -> "#007229"
    HammersmithAndCity -> "#E899A8"
    Jubilee -> "#686E72"
    Metropolitan -> "#893267"
    Northern -> "#000000"
    Piccadilly -> "#0450A1"
    Victoria -> "#009FE0"
    WaterlooAndCity -> "#70C3CE"
  }
}

pub type Point {
  Point(longitude: Float, latitude: Float)
}

pub type LineInfo {
  LineInfo(line: Line, branches: List(List(Point)))
}
