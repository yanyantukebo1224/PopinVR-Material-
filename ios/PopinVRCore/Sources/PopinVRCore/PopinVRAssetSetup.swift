import Combine
import CoreML
import CryptoKit
import Foundation
import ZIPFoundation

/// First-run, blocking setup for the HaMeR + SOMA-X runtime assets.
/// The app must not enter the headset runtime until this completes.
@MainActor
public final class PopinVRAssetSetup: ObservableObject {
    public enum State: Equatable {
        case idle
        case downloadingModel
        case extractingModel
        case compilingModel
        case downloadingSOMA
        case extractingSOMA
        case ready
        case failed(String)
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var detail: String = "Checking required runtime assets…"

    public struct Assets {
        public let hamerModelURL: URL
        public let compiledHaMeRURL: URL
        public let somaDirectoryURL: URL
        public let somaRegressorURL: URL
        public let somaParametersURL: URL
    }

    private let fileManager = FileManager.default
    private let baseURL: URL
    private let modelArchiveURL = URL(string: "https://github.com/VimalMollyn/fasterhamer/releases/download/assets-v2/fasthamer-assets-v2.zip")!
    private let somaArchiveURL = URL(string: "https://github.com/VimalMollyn/fasterhamer/releases/download/soma-v2/fasthamer-soma-v2.zip")!
    private let modelSHA256 = "5ff4745a5a0cc48b1bd18e55867f177cccb982d1dc1dd1d6b06090c3e0a5e7d8"
    private let somaSHA256 = "14e018b3f931968d9f89f51a68812ef72b1ba35f8d88d6d9a569d84d4e886122"

    public init(baseURL: URL? = nil) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.baseURL = baseURL ?? support.appendingPathComponent("PopinVR/RuntimeAssets", isDirectory: true)
    }

    /// Downloads, verifies, extracts and compiles assets. Calling this repeatedly is safe:
    /// already verified assets are reused and the operation can run offline after first setup.
    public func prepare() async throws -> Assets {
        do {
            try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
            let modelDir = baseURL.appendingPathComponent("fasthamer-assets-v2", isDirectory: true)
            let somaDir = baseURL.appendingPathComponent("fasthamer-soma-v2", isDirectory: true)
            let modelPackage = modelDir.appendingPathComponent("hamer_params.mlpackage", isDirectory: true)
            let somaParams = somaDir.appendingPathComponent("mano2somax_resmlp512x4_numpy.npz")
            let somaRegressor = somaDir.appendingPathComponent("mano2somax_regressor_fp32.mlpackage", isDirectory: true)

            if !fileManager.fileExists(atPath: modelPackage.path) {
                state = .downloadingModel
                detail = "Downloading HaMeR model (~470 MB)…"
                let archive = try await downloadVerified(from: modelArchiveURL, sha256: modelSHA256, name: "hamer-assets.zip")
                state = .extractingModel
                detail = "Verifying and extracting HaMeR model…"
                try extract(archive, to: modelDir, expectedItem: "hamer_params.mlpackage")
            }

            guard fileManager.fileExists(atPath: modelPackage.path) else {
                throw SetupError.missingAsset("hamer_params.mlpackage")
            }

            if !fileManager.fileExists(atPath: somaParams.path) || !fileManager.fileExists(atPath: somaRegressor.path) {
                state = .downloadingSOMA
                detail = "Downloading SOMA-X hand model (~40 MB)…"
                let archive = try await downloadVerified(from: somaArchiveURL, sha256: somaSHA256, name: "soma-assets.zip")
                state = .extractingSOMA
                detail = "Extracting SOMA-X model and geometry data…"
                try extract(archive, to: somaDir, expectedItem: "mano2somax_resmlp512x4_numpy.npz")
            }

            guard fileManager.fileExists(atPath: somaParams.path),
                  fileManager.fileExists(atPath: somaRegressor.path) else {
                throw SetupError.missingAsset("SOMA-X regressor or parameter archive")
            }

            let compiledURL = baseURL.appendingPathComponent("hamer_params.compiled", isDirectory: true)
            if !fileManager.fileExists(atPath: compiledURL.path) {
                state = .compilingModel
                detail = "Compiling HaMeR for this iPhone. First launch can take a while…"
                let temporary = try MLModel.compileModel(at: modelPackage)
                if fileManager.fileExists(atPath: compiledURL.path) {
                    try fileManager.removeItem(at: compiledURL)
                }
                try fileManager.moveItem(at: temporary, to: compiledURL)
            }

            state = .ready
            detail = "All required models are installed."
            return Assets(
                hamerModelURL: modelPackage,
                compiledHaMeRURL: compiledURL,
                somaDirectoryURL: somaDir,
                somaRegressorURL: somaRegressor,
                somaParametersURL: somaParams
            )
        } catch {
            state = .failed(error.localizedDescription)
            detail = error.localizedDescription
            throw error
        }
    }

    private func downloadVerified(from remoteURL: URL, sha256: String, name: String) async throws -> URL {
        let destination = baseURL.appendingPathComponent(name)
        if fileManager.fileExists(atPath: destination.path) {
            if try digest(of: destination) == sha256 { return destination }
            try fileManager.removeItem(at: destination)
        }
        let (temporaryURL, _) = try await URLSession.shared.download(from: remoteURL)
        let actual = try digest(of: temporaryURL)
        guard actual == sha256 else { throw SetupError.checksumMismatch(name) }
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func digest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 1024 * 1024)
            if data.isEmpty { return false }
            hasher.update(data: data)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func extract(_ archiveURL: URL, to destination: URL, expectedItem: String) throws {
        let staging = baseURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        guard let archive = Archive(url: archiveURL, accessMode: .read) else {
            throw SetupError.invalidArchive(archiveURL.lastPathComponent)
        }
        for entry in archive {
            let output = staging.appendingPathComponent(entry.path).standardizedFileURL
            guard output.path.hasPrefix(staging.standardizedFileURL.path + "/") else {
                throw SetupError.invalidArchive("Unsafe archive path")
            }
            _ = try archive.extract(entry, to: output)
        }

        let candidate = locate(expectedItem, under: staging)
        guard let root = candidate?.deletingLastPathComponent() else {
            throw SetupError.missingAsset(expectedItem)
        }
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.moveItem(at: root, to: destination)
    }

    private func locate(_ name: String, under root: URL) -> URL? {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == name {
            return url
        }
        return nil
    }

    public enum SetupError: LocalizedError {
        case checksumMismatch(String)
        case invalidArchive(String)
        case missingAsset(String)

        public var errorDescription: String? {
            switch self {
            case .checksumMismatch(let name): return "\(name) failed SHA-256 verification. The download was discarded."
            case .invalidArchive(let name): return "The downloaded archive is invalid: \(name)"
            case .missingAsset(let name): return "The model archive did not contain the required asset: \(name)"
            }
        }
    }
}
