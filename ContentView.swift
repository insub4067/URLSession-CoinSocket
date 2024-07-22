import SwiftUI

struct ContentView: View {
    
    @StateObject var socket = CoinSocket()
    
    var body: some View {
        if !socket.bitcoinPrice.isEmpty {
            Text("Bitcoin Price(USD): \(socket.bitcoinPrice)")
                .font(.title2)
        }
    }
}

class CoinSocket: NSObject, ObservableObject {
    
    @Published var isConnected = false
    @Published var bitcoinPrice = ""
    
    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?
    
    
    override init() {
        super.init()
        self.connect("wss://ws.coincap.io/prices?assets=bitcoin")
        self.receive()
    }
    
    func connect(_ urlString: String) {
        let url = URL(string: urlString)!
        task = session.webSocketTask(with: url)
        task?.delegate = self
        task?.resume()
    }
    
    func receive() {
        task?.receive(completionHandler: { result in
            switch result {
            case .success(let success):
                switch success {
                case .data(let data):
                    guard let response = try? JSONDecoder().decode(SocketResponse.self, from: data) else { return }
                    Task { @MainActor in
                        self.bitcoinPrice = response.bitcoin
                    }
                    
                case .string(let string):
                    guard
                        let data = string.data(using: .utf8),
                        let response = try? JSONDecoder().decode(SocketResponse.self, from: data)
                    else { return }
                    Task { @MainActor in
                        self.bitcoinPrice = response.bitcoin
                    }
                    
                default:
                    break
                }
                self.receive()
            case .failure(let failure):
                print("Error: ", failure)
            }
        })
    }
    
    func send(_ message: String) {
        let message = URLSessionWebSocketTask.Message.string(message)
        task?.send(message) { error in
            if let error = error {
                print("Error sending message: \(error)")
            }
        }
    }
    
    func send(_ image: UIImage) {
        guard let imageData = image.jpegData(compressionQuality: 1.0) else { return }
        let message = URLSessionWebSocketTask.Message.data(imageData)
        task?.send(message) { error in
            if let error = error {
                print("Error sending image: \(error)")
            }
        }
    }
    
    func disconnect() {
        self.task?.cancel()
        self.task = nil
    }
    
    deinit {
        self.disconnect()
    }
}

extension CoinSocket: URLSessionWebSocketDelegate {
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            self.isConnected = true
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            self.isConnected = false
        }
    }
}

struct SocketResponse: Codable {
    let bitcoin: String
}
