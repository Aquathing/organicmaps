#pragma once

#include "kml/types.hpp"

#include "geometry/point_with_altitude.hpp"
#include "geometry/latlon.hpp"

#include <cstdint>
#include <string>
#include <vector>

struct ElevationInfo
{
public:
  struct Point
  {
    Point(geometry::PointWithAltitude point, double distance)
    : m_point(point), m_distance(distance)
    {
    }
    geometry::PointWithAltitude m_point;
    double m_distance;
  };

  using Points = std::vector<Point>;
  using SegmentDistances = std::vector<double>;

  enum Difficulty : uint8_t
  {
    Unknown,
    Easy,
    Medium,
    Hard
  };

  ElevationInfo() = default;
  explicit ElevationInfo(kml::MultiGeometry const & geometry);

  size_t GetSize() const { return m_points.size(); };
  Points const & GetPoints() const { return m_points; };
  geometry::Altitude GetAscent() const { return m_ascent; }
  geometry::Altitude GetDescent() const { return m_descent; }
  geometry::Altitude GetMinAltitude() const { return m_minAltitude; }
  geometry::Altitude GetMaxAltitude() const { return m_maxAltitude; }
  uint8_t GetDifficulty() const { return m_difficulty; }
  SegmentDistances const & GetSegmentDistances() const { return m_segmentDistances; };

private:
  // Points with distance from start of the track and altitude.
  Points m_points;
  // Ascent in meters.
  geometry::Altitude m_ascent = 0;
  // Descent in meters.
  geometry::Altitude m_descent = 0;
  // Altitude in meters.
  geometry::Altitude m_minAltitude = 0;
  // Altitude in meters.
  geometry::Altitude m_maxAltitude = 0;
  // Some digital difficulty level with value in range [0-kMaxDifficulty]
  // or kInvalidDifficulty when difficulty is not found or incorrect.
  Difficulty m_difficulty = Difficulty::Unknown;
  // Distances to the start of each segment.
  SegmentDistances m_segmentDistances;
};
