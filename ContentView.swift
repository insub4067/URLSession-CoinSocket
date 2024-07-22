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
    var pingCount = 0
    
    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?
    
    
    override init() {
        super.init()
        self.connect()
        self.receive()
    }
    
    func connect() {
        let url = URL(string: "wss://ws.coincap.io/prices?assets=bitcoin")!
        task = session.webSocketTask(with: url)
        task?.delegate = self
        task?.resume()
        self.startPing()
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
    
    func startPing() {
        Task { [weak self] in
            guard let id = self?.task?.taskIdentifier else { return }
            try await Task.sleep(for: .seconds(5))
            
            guard let self, self.task?.taskIdentifier == id else { return }
            if self.task?.state == .running, self.pingCount < 2  {
                self.pingCount += 1
                self.task?.sendPing(pongReceiveHandler: { [weak self] _ in
                    if self?.task?.taskIdentifier == id {
                        self?.pingCount = 0
                    }
                })
                self.startPing()
            } else {
                self.reconnect()
            }
        }
    }
    
    func reconnect() {
        self.disconnect()
        self.connect()
    }
    
    func disconnect() {
        self.task?.cancel()
        self.task = nil
        self.pingCount = 0
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
