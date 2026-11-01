// Cross-checks JSBSim's frames against src/geo/geo_math, as JSBSimAircraft uses them: JSBSim's ECEF location
// against geodetic_to_ecef of its own geodetic position, and its body-to-ECEF matrix (Tb2ec) against its own
// heading / pitch / roll (local NED Euler angles). Links the JSBSim shared library; no Godot needed.
#include <doctest.h>

#include <cmath>

#include <FGFDMExec.h>
#include <initialization/FGInitialCondition.h>
#include <models/FGPropagate.h>

#include "geo/geo_math.h"

using namespace gjsb::geo;

namespace {

constexpr double PI = 3.14159265358979323846;
constexpr double M_PER_FT = 0.3048;
double rad(double degrees) { return degrees * PI / 180.0; }

struct Case {
	double lat, lon, height_ft, heading, pitch, roll;
};

const Case CASES[] = {
	{ 39.95, 32.69, 5000, 0, 0, 0 },
	{ 39.95, 32.69, 5000, 90, 5, -10 },
	{ 41.0, 28.98, 1000, 225, -12, 30 },
	{ -33.87, 151.21, 30000, 315, 20, 60 },
	{ 0.0, 0.0, 100, 45, 1, 1 },
	{ 0.0, 180.0, 100, 180, -30, -80 },
	{ 70.0, -150.0, 20000, 10, 45, 170 },
	{ -80.0, 10.0, 3000, 300, -60, 5 },
};

Mat3 to_mat3(const JSBSim::FGMatrix33 &m) {
	Mat3 r;
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			r.m[i][j] = m(i + 1, j + 1);
		}
	}
	return r;
}

double angle_diff(double a, double b) {
	return std::abs(std::remainder(a - b, 2.0 * PI));
}

} // namespace

TEST_CASE("JSBSim frames match geo_math") {
	JSBSim::FGFDMExec fdm;
	fdm.SetDebugLevel(0);
	fdm.SetRootDir(SGPath(DATA_DIR));
	fdm.SetAircraftPath(SGPath("aircraft"));
	fdm.SetEnginePath(SGPath("engine"));
	fdm.SetSystemsPath(SGPath("systems"));
	REQUIRE(fdm.LoadModel("J3Cub"));

	for (const Case &c : CASES) {
		CAPTURE(c.lat);
		CAPTURE(c.lon);
		CAPTURE(c.heading);
		CAPTURE(c.pitch);
		CAPTURE(c.roll);
		auto ic = fdm.GetIC();
		ic->SetGeodLatitudeDegIC(c.lat);
		ic->SetLongitudeDegIC(c.lon);
		ic->SetAltitudeASLFtIC(c.height_ft);
		ic->SetPsiDegIC(c.heading);
		ic->SetThetaDegIC(c.pitch);
		ic->SetPhiDegIC(c.roll);
		ic->SetVcalibratedKtsIC(80.0);
		REQUIRE(fdm.RunIC());

		const auto propagate = fdm.GetPropagate();
		const double lat = rad(fdm.GetPropertyValue("position/lat-geod-deg"));
		const double lon = rad(fdm.GetPropertyValue("position/long-gc-deg"));
		const double height = fdm.GetPropertyValue("position/geod-alt-ft") * M_PER_FT;

		// Position: JSBSim's ECEF (ft) is the WGS84 ECEF of its geodetic position.
		const JSBSim::FGLocation &loc = propagate->GetLocation();
		const Vec3 ecef{ loc(1) * M_PER_FT, loc(2) * M_PER_FT, loc(3) * M_PER_FT };
		CHECK((ecef - geodetic_to_ecef({ lat, lon, height })).length() < 1e-3);

		// Orientation: Tb2ec seen from the local NED frame gives JSBSim's own Euler angles.
		const Mat3 body_to_ned = ned_to_ecef_rotation(lat, lon).transposed() * to_mat3(propagate->GetTb2ec());
		const Euler e = matrix_to_euler(body_to_ned);
		CHECK(angle_diff(e.z, fdm.GetPropertyValue("attitude/psi-rad")) < 1e-9);
		CHECK(angle_diff(e.y, fdm.GetPropertyValue("attitude/theta-rad")) < 1e-9);
		CHECK(angle_diff(e.x, fdm.GetPropertyValue("attitude/phi-rad")) < 1e-9);
		// And the requested initial condition (pitch beyond ±90° is not used here).
		CHECK(angle_diff(e.z, rad(c.heading)) < 1e-9);
		CHECK(angle_diff(e.y, rad(c.pitch)) < 1e-9);
		CHECK(angle_diff(e.x, rad(c.roll)) < 1e-9);
	}
}
