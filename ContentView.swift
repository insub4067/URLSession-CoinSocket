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
        self.connect()
        self.recieve()
    }
    
    func connect() {
        let url = URL(string: "wss://ws.coincap.io/prices?assets=bitcoin")!
        task = session.webSocketTask(with: url)
        task?.delegate = self
        task?.resume()
    }
    
    func recieve() {
        task?.receive(completionHandler: { result in
            switch result {
            case .success(let success):
                switch success {
                case .data(let data):
                    break
                    
                case .string(let string):
                    guard
                        let data = string.data(using: .utf8),
                        let response = try? JSONDecoder().decode(SocketResponse.self, from: data)
                    else { return }
                    Task { @MainActor in
                        self.bitcoinPrice = response.bitcoin
                    }
                    
                @unknown default:
                    break
                }
                self.recieve()
            case .failure(let failure):
                print("Error: ", failure)
            }
        })
    }
    
    func disconnect() {
        self.task?.cancel()
        self.task = nil
    }
    
    deinit {
        self.disconnect()
    }
}

struct SocketResponse: Codable {
    let bitcoin: String
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
