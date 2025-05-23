import geos

public extension GeometryConvertible {

    // MARK: - Misc Functions

    func length() throws -> Double {
        let context = try GEOSContext()
        let geosObject = try geometry.geosObject(with: context)
        var length: Double = 0
        // returns 0 on exception
        guard GEOSLength_r(context.handle, geosObject.pointer, &length) != 0 else {
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
        return length
    }

    func distance(to geometry: GeometryConvertible) throws -> Double {
        let context = try GEOSContext()
        let geosObject = try self.geometry.geosObject(with: context)
        let otherGeosObject = try geometry.geometry.geosObject(with: context)
        var dist: Double = 0
        // returns 0 on exception
        guard GEOSDistance_r(context.handle, geosObject.pointer, otherGeosObject.pointer, &dist) != 0 else {
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
        return dist
    }

    func hausdorffDistance(to geometry: GeometryConvertible) throws -> Double {
        let context = try GEOSContext()
        let geosObject = try self.geometry.geosObject(with: context)
        let otherGeosObject = try geometry.geometry.geosObject(with: context)

        var distance: Double = 0
        // returns 0 on exception
        guard GEOSHausdorffDistance_r(
            context.handle,
            geosObject.pointer,
            otherGeosObject.pointer,
            &distance
        ) == 1 else {
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
        return distance
    }

    func hausdorffDistanceDensify(
        to geometry: GeometryConvertible,
        densifyFraction: Double
    ) throws -> Double {
        let context = try GEOSContext()
        let geosObject = try self.geometry.geosObject(with: context)
        let otherGeosObject = try geometry.geometry.geosObject(with: context)

        var distance: Double = 0
        // returns 0 on exception
        guard GEOSHausdorffDistanceDensify_r(
            context.handle,
            geosObject.pointer,
            otherGeosObject.pointer,
            densifyFraction,
            &distance
        ) == 1 else {
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
        return distance
    }

    func area() throws -> Double {
        let context = try GEOSContext()
        let geosObject = try geometry.geosObject(with: context)
        var area: Double = 0
        // returns 0 on exception
        guard GEOSArea_r(context.handle, geosObject.pointer, &area) != 0 else {
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
        return area
    }

    func nearestPoints(with geometry: GeometryConvertible) throws -> [Point] {
        let context = try GEOSContext()
        let geosObject = try self.geometry.geosObject(with: context)
        let otherGeosObject = try geometry.geometry.geosObject(with: context)
        guard let coordSeq = GEOSNearestPoints_r(
            context.handle, geosObject.pointer, otherGeosObject.pointer) else {
                throw GEOSError.libraryError(errorMessages: context.errors)
        }
        defer { GEOSCoordSeq_destroy_r(context.handle, coordSeq) }
        var point0 = Point(x: 0, y: 0)
        GEOSCoordSeq_getX_r(context.handle, coordSeq, 0, &point0.x)
        GEOSCoordSeq_getY_r(context.handle, coordSeq, 0, &point0.y)
        var point1 = Point(x: 0, y: 0)
        GEOSCoordSeq_getX_r(context.handle, coordSeq, 1, &point1.x)
        GEOSCoordSeq_getY_r(context.handle, coordSeq, 1, &point1.y)
        return [point0, point1]
    }

    // MARK: - Unary Predicates

    internal typealias UnaryPredicate = (GEOSContextHandle_t, OpaquePointer) -> Int8

    internal func evaluateUnaryPredicate(_ predicate: UnaryPredicate) throws -> Bool {
        let context = try GEOSContext()
        let geosObject = try geometry.geosObject(with: context)
        // returns 2 on exception, 1 on true, 0 on false
        let result = predicate(context.handle, geosObject.pointer)
        guard result != 2 else {
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
        return result == 1
    }

    func isEmpty() throws -> Bool {
        try evaluateUnaryPredicate(GEOSisEmpty_r)
    }

    func isRing() throws -> Bool {
        try evaluateUnaryPredicate(GEOSisRing_r)
    }

    func isValid() throws -> Bool {
        try evaluateUnaryPredicate(GEOSisValid_r)
    }

    func isValidReason() throws -> String {
        let context = try GEOSContext()
        let geosObject = try self.geometry.geosObject(with: context)
        guard let cString = GEOSisValidReason_r(context.handle, geosObject.pointer) else {
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
        defer { GEOSFree_r(context.handle, cString) }
        return String(cString: cString)
    }

    func isValidDetail(allowSelfTouchingRingFormingHole: Bool = false) throws -> IsValidDetailResult {
        let context = try GEOSContext()
        let geosObject = try self.geometry.geosObject(with: context)
        let flags: Int32 = allowSelfTouchingRingFormingHole
            ? Int32(GEOSVALID_ALLOW_SELFTOUCHING_RING_FORMING_HOLE.rawValue)
            : 0
        var optionalReason: UnsafeMutablePointer<Int8>?
        var optionalLocation: OpaquePointer?
        switch GEOSisValidDetail_r(
            context.handle, geosObject.pointer, flags, &optionalReason, &optionalLocation) {
        case 1: // Valid
            if let reason = optionalReason {
                GEOSFree_r(context.handle, reason)
            }
            if let location = optionalLocation {
                GEOSGeom_destroy_r(context.handle, location)
            }
            return .valid
        case 0: // Invalid
            let reason = optionalReason.map { (reason) -> String in
                defer { GEOSFree_r(context.handle, reason) }
                return String(cString: reason)
            }
            let location = try optionalLocation.map { (location) -> Geometry in
                let locationGEOSObject = GEOSObject(context: context, pointer: location)
                return try Geometry(geosObject: locationGEOSObject)
            }
            return .invalid(reason: reason, location: location)
        default: // Error
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
    }

    // MARK: - Binary Predicates

    private typealias BinaryPredicate = (GEOSContextHandle_t, OpaquePointer, OpaquePointer) -> Int8

    private func evaluateBinaryPredicate(
        _ predicate: BinaryPredicate,
        with geometry: GeometryConvertible
    ) throws -> Bool {
        let context = try GEOSContext()
        let geosObject = try self.geometry.geosObject(with: context)
        let otherGeosObject = try geometry.geometry.geosObject(with: context)
        // returns 2 on exception, 1 on true, 0 on false
        let result = predicate(context.handle, geosObject.pointer, otherGeosObject.pointer)
        guard result != 2 else {
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
        return result == 1
    }

    func isTopologicallyEquivalent(to geometry: GeometryConvertible) throws -> Bool {
        try evaluateBinaryPredicate(GEOSEquals_r, with: geometry)
    }

    func isDisjoint(with geometry: GeometryConvertible) throws -> Bool {
        try evaluateBinaryPredicate(GEOSDisjoint_r, with: geometry)
    }

    func touches(_ geometry: GeometryConvertible) throws -> Bool {
        try evaluateBinaryPredicate(GEOSTouches_r, with: geometry)
    }

    func intersects(_ geometry: GeometryConvertible) throws -> Bool {
        try evaluateBinaryPredicate(GEOSIntersects_r, with: geometry)
    }

    func crosses(_ geometry: GeometryConvertible) throws -> Bool {
        try evaluateBinaryPredicate(GEOSCrosses_r, with: geometry)
    }

    func isWithin(_ geometry: GeometryConvertible) throws -> Bool {
        try evaluateBinaryPredicate(GEOSWithin_r, with: geometry)
    }

    func contains(_ geometry: GeometryConvertible) throws -> Bool {
        try evaluateBinaryPredicate(GEOSContains_r, with: geometry)
    }

    func overlaps(_ geometry: GeometryConvertible) throws -> Bool {
        try evaluateBinaryPredicate(GEOSOverlaps_r, with: geometry)
    }

    func covers(_ geometry: GeometryConvertible) throws -> Bool {
        try evaluateBinaryPredicate(GEOSCovers_r, with: geometry)
    }

    func isCovered(by geometry: GeometryConvertible) throws -> Bool {
        try evaluateBinaryPredicate(GEOSCoveredBy_r, with: geometry)
    }

    // MARK: - Prepared Geometry

    func makePrepared() throws -> PreparedGeometry {
        let context = try GEOSContext()
        let geosObject = try geometry.geosObject(with: context)
        return try PreparedGeometry(context: context, base: geosObject)
    }

    // MARK: - Dimensionally Extended 9 Intersection Model Functions

    /// Parameter mask: A DE9-IM mask pattern
    func relate(_ geometry: GeometryConvertible, mask: String) throws -> Bool {
        let context = try GEOSContext()
        let geosObject = try self.geometry.geosObject(with: context)
        let otherGeosObject = try geometry.geometry.geosObject(with: context)
        // returns 2 on exception, 1 on true, 0 on false
        let result = mask.withCString {
            GEOSRelatePattern_r(context.handle, geosObject.pointer, otherGeosObject.pointer, $0)
        }
        guard result != 2 else {
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
        return result == 1
    }

    func relate(_ geometry: GeometryConvertible) throws -> String {
        let context = try GEOSContext()
        let geosObject = try self.geometry.geosObject(with: context)
        let otherGeosObject = try geometry.geometry.geosObject(with: context)
        guard let cString = GEOSRelate_r(context.handle, geosObject.pointer, otherGeosObject.pointer) else {
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
        defer { GEOSFree_r(context.handle, cString) }
        return String(cString: cString)
    }

    // MARK: - Topology Operations

    internal typealias UnaryOperation = (GEOSContextHandle_t, OpaquePointer) -> OpaquePointer?

    internal func performUnaryTopologyOperation<T>(_ operation: UnaryOperation) throws -> T
        where T: GEOSObjectInitializable {
            let context = try GEOSContext()
            let geosObject = try geometry.geosObject(with: context)
            guard let pointer = operation(context.handle, geosObject.pointer) else {
                throw GEOSError.libraryError(errorMessages: context.errors)
            }
            return try T(geosObject: GEOSObject(context: context, pointer: pointer))
    }

    private typealias BinaryOperation = (GEOSContextHandle_t, OpaquePointer, OpaquePointer) -> OpaquePointer?

    private func performBinaryTopologyOperation(
        _ operation: BinaryOperation,
        geometry: GeometryConvertible
    ) throws -> Geometry {
        let context = try GEOSContext()
        let geosObject = try self.geometry.geosObject(with: context)
        let otherGeosObject = try geometry.geometry.geosObject(with: context)
        guard let pointer = operation(context.handle, geosObject.pointer, otherGeosObject.pointer) else {
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
        return try Geometry(geosObject: GEOSObject(context: context, pointer: pointer))
    }

    func envelope() throws -> Envelope {
        let geometry: Geometry = try performUnaryTopologyOperation(GEOSEnvelope_r)
        switch geometry {
        case let .point(point):
            return Envelope(minX: point.x, maxX: point.x, minY: point.y, maxY: point.y)
        case let .polygon(polygon):
            var minX = Double.nan
            var maxX = Double.nan
            var minY = Double.nan
            var maxY = Double.nan
            for point in polygon.exterior.points {
                minX = .minimum(minX, point.x)
                maxX = .maximum(maxX, point.x)
                minY = .minimum(minY, point.y)
                maxY = .maximum(maxY, point.y)
            }
            return Envelope(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
        default:
            throw GEOSwiftError.unexpectedEnvelopeResult(geometry)
        }
    }

    func intersection(with geometry: GeometryConvertible) throws -> Geometry? {
        do {
            return try performBinaryTopologyOperation(GEOSIntersection_r, geometry: geometry)
        } catch GEOSwiftError.tooFewPoints {
            return nil
        } catch {
            throw error
        }
    }

    func makeValid() throws -> Geometry {
        try performUnaryTopologyOperation(GEOSMakeValid_r)
    }

    func makeValid(method: MakeValidMethod) throws -> Geometry {
        let context = try GEOSContext()
        let geosObject = try geometry.geosObject(with: context)
        let params = MakeValidParams(context: context, method: method)
        guard let pointer = GEOSMakeValidWithParams_r(
            context.handle,
            geosObject.pointer,
            params.pointer
        ) else {
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
        return try Geometry(geosObject: GEOSObject(context: context, pointer: pointer))
    }

    func normalized() throws -> Geometry {
        let context = try GEOSContext()
        let geosObject = try geometry.geosObject(with: context)
        // GEOSNormalize_r returns -1 on exception
        guard GEOSNormalize_r(context.handle, geosObject.pointer) != -1 else {
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
        return try Geometry(geosObject: geosObject)
    }

    func convexHull() throws -> Geometry {
        try performUnaryTopologyOperation(GEOSConvexHull_r)
    }

    func concaveHull(withRatio ratio: Double, allowHoles: Bool) throws -> Geometry {
        let context = try GEOSContext()
        let geosObject = try geometry.geosObject(with: context)
        guard let resultPointer = GEOSConcaveHull_r(
            context.handle,
            geosObject.pointer,
            ratio,
            allowHoles ? 1 : 0
        ) else {
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
        return try Geometry(geosObject: GEOSObject(context: context, pointer: resultPointer))
    }

    func minimumRotatedRectangle() throws -> Geometry {
        try performUnaryTopologyOperation(GEOSMinimumRotatedRectangle_r)
    }

    func minimumWidth() throws -> LineString {
        try performUnaryTopologyOperation(GEOSMinimumWidth_r)
    }

    func difference(with geometry: GeometryConvertible) throws -> Geometry? {
        do {
            return try performBinaryTopologyOperation(GEOSDifference_r, geometry: geometry)
        } catch GEOSwiftError.tooFewPoints {
            return nil
        } catch {
            throw error
        }
    }

    func symmetricDifference(with geometry: GeometryConvertible) throws -> Geometry? {
        do {
            return try performBinaryTopologyOperation(GEOSSymDifference_r, geometry: geometry)
        } catch GEOSwiftError.tooFewPoints {
            return nil
        } catch {
            throw error
        }
    }

    func union(with geometry: GeometryConvertible) throws -> Geometry {
        try performBinaryTopologyOperation(GEOSUnion_r, geometry: geometry)
    }

    func unaryUnion() throws -> Geometry {
        try performUnaryTopologyOperation(GEOSUnaryUnion_r)
    }

    func pointOnSurface() throws -> Point {
        try performUnaryTopologyOperation(GEOSPointOnSurface_r)
    }

    func centroid() throws -> Point {
        try performUnaryTopologyOperation(GEOSGetCentroid_r)
    }

    func minimumBoundingCircle() throws -> Circle {
        let context = try GEOSContext()
        let geosObject = try geometry.geosObject(with: context)
        var radius: Double = 0
        var optionalCenterPointer: OpaquePointer?
        guard let geometryPointer = GEOSMinimumBoundingCircle_r(
            context.handle, geosObject.pointer, &radius, &optionalCenterPointer) else {
                // if we somehow end up with a non-null center and a null geometry,
                // we must still destroy the center before throwing an error
                if let centerPointer = optionalCenterPointer {
                    GEOSGeom_destroy_r(context.handle, centerPointer)
                }
                throw GEOSError.libraryError(errorMessages: context.errors)
        }
        // For our purposes, we only care about the center and radius.
        GEOSGeom_destroy_r(context.handle, geometryPointer)
        guard let centerPointer = optionalCenterPointer else {
            throw GEOSError.noMinimumBoundingCircle
        }
        let center = try Point(geosObject: GEOSObject(context: context, pointer: centerPointer))
        return Circle(center: center, radius: radius)
    }

    func polygonize() throws -> GeometryCollection {
        try [self].polygonize()
    }

    func lineMerge() throws -> Geometry {
        try performUnaryTopologyOperation(GEOSLineMerge_r)
    }

    func lineMergeDirected() throws -> Geometry {
        try performUnaryTopologyOperation(GEOSLineMergeDirected_r)
    }

    // MARK: - Buffer Functions

    func buffer(by width: Double) throws -> Geometry? {
        let context = try GEOSContext()
        let geosObject = try geometry.geosObject(with: context)
        // the last parameter in GEOSBuffer_r is called `quadsegs` and in other places in GEOS, it defaults to
        // 8, which seems to produce an "expected" result. See https://github.com/GEOSwift/GEOSwift/issues/216
        //
        // returns nil on exception
        guard let resultPointer = GEOSBuffer_r(context.handle, geosObject.pointer, width, 8) else {
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
        do {
            return try Geometry(geosObject: GEOSObject(context: context, pointer: resultPointer))
        } catch GEOSwiftError.tooFewPoints {
            return nil
        } catch {
            throw error
        }
    }

    func bufferWithStyle(
        width: Double,
        quadsegs: Int32 = 8,
        endCapStyle: BufferEndCapStyle = .round,
        joinStyle: BufferJoinStyle = .round,
        mitreLimit: Double = 5.0
    ) throws -> Geometry? {
        let context = try GEOSContext()
        let geosObject = try geometry.geosObject(with: context)

        guard let resultPointer = GEOSBufferWithStyle_r(
            context.handle,
            geosObject.pointer,
            width,
            quadsegs,
            Int32(endCapStyle.geosValue.rawValue),
            Int32(joinStyle.geosValue.rawValue),
            mitreLimit
        ) else {
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
        do {
            return try Geometry(geosObject: GEOSObject(context: context, pointer: resultPointer))
        } catch GEOSwiftError.tooFewPoints {
            return nil
        } catch {
            throw error
        }
    }

    func offsetCurve(
        width: Double,
        quadsegs: Int32 = 8,
        joinStyle: BufferJoinStyle = .bevel,
        mitreLimit: Double = 5.0
    ) throws -> Geometry? {
        let context = try GEOSContext()
        let geosObject = try geometry.geosObject(with: context)

        guard let resultPointer = GEOSOffsetCurve_r(
            context.handle,
            geosObject.pointer,
            width,
            quadsegs,
            Int32(joinStyle.geosValue.rawValue),
            mitreLimit
        ) else {
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
        do {
            return try Geometry(geosObject: GEOSObject(context: context, pointer: resultPointer))
        } catch GEOSwiftError.tooFewPoints {
            return nil
        } catch {
            throw error
        }
    }

    // MARK: - Simplify Functions

    func simplify(withTolerance tolerance: Double) throws -> Geometry {
        let context = try GEOSContext()
        let geosObject = try geometry.geosObject(with: context)
        guard let resultPointer = GEOSSimplify_r(context.handle, geosObject.pointer, tolerance) else {
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
        return try Geometry(geosObject: GEOSObject(context: context, pointer: resultPointer))
    }

    // MARK: - Snapping

    func snap(to geometry: GeometryConvertible, tolerance: Double) throws -> Geometry {
        let context = try GEOSContext()
        let geosObject = try self.geometry.geosObject(with: context)
        let otherGeosObject = try geometry.geometry.geosObject(with: context)
        guard let pointer = GEOSSnap_r(
            context.handle,
            geosObject.pointer,
            otherGeosObject.pointer,
            tolerance
        ) else {
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
        return try Geometry(geosObject: GEOSObject(context: context, pointer: pointer))
    }
}

public extension Collection where Element: GeometryConvertible {
    func polygonize() throws -> GeometryCollection {
        let context = try GEOSContext()
        let geosObjects = try map { try $0.geometry.geosObject(with: context) }
        let pointer = withExtendedLifetime(geosObjects) { geosObjects in
            GEOSPolygonize_r(context.handle, geosObjects.map { $0.pointer }, UInt32(geosObjects.count))
        }
        guard let pointer else {
            throw GEOSError.libraryError(errorMessages: context.errors)
        }
        return try GeometryCollection(geosObject: GEOSObject(context: context, pointer: pointer))
    }
}

public enum BufferEndCapStyle: Hashable, Sendable {
    case round
    case flat
    case square

    var geosValue: GEOSBufCapStyles {
        switch self {
        case .round:
            return GEOSBUF_CAP_ROUND
        case .flat:
            return GEOSBUF_CAP_FLAT
        case .square:
            return GEOSBUF_CAP_SQUARE
        }
    }
}

public enum BufferJoinStyle: Hashable, Sendable {
    case round
    case mitre
    case bevel

    var geosValue: GEOSBufJoinStyles {
        switch self {
        case .round:
            return GEOSBUF_JOIN_ROUND
        case .mitre:
            return GEOSBUF_JOIN_MITRE
        case .bevel:
            return GEOSBUF_JOIN_BEVEL
        }
    }
}

public enum IsValidDetailResult: Hashable, Sendable {
    case valid
    case invalid(reason: String?, location: Geometry?)
}

public enum MakeValidMethod {
    case linework
    case structure(keepCollapsed: Bool)

    var geosMethod: GEOSMakeValidMethods {
        switch self {
        case .linework:
            return GEOS_MAKE_VALID_LINEWORK
        case .structure:
            return GEOS_MAKE_VALID_STRUCTURE
        }
    }

    var keepCollapsed: Int32? {
        switch self {
        case .linework:
            return nil
        case .structure(let keepCollapsed):
            return keepCollapsed ? 1 : 0
        }
    }
}

private class MakeValidParams {
    let context: GEOSContext
    let pointer: OpaquePointer

    init(context: GEOSContext, method: MakeValidMethod) {
        self.context = context
        self.pointer = GEOSMakeValidParams_create_r(context.handle)
        assert(GEOSMakeValidParams_setMethod_r(context.handle, pointer, method.geosMethod) == 1)
        if let keepCollapsed = method.keepCollapsed {
            assert(GEOSMakeValidParams_setKeepCollapsed_r(context.handle, pointer, keepCollapsed) == 1)
        }
    }

    deinit {
        GEOSMakeValidParams_destroy_r(context.handle, pointer)
    }
}
