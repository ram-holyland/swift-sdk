//
//
//  Created by Tapash Majumder on 7/24/18.
//  Copyright © 2018 Iterable. All rights reserved.
//

import Foundation

typealias SendRequestValue = [AnyHashable : Any]

struct SendRequestError : Error {
    let reason: String?
    let data: Data?
    
    init(reason: String? = nil, data: Data? = nil) {
        self.reason = reason
        self.data = data
    }
    
    static func createErroredFuture(reason: String? = nil) -> Future<SendRequestValue> {
        return Promise<SendRequestValue>(error: SendRequestError(reason: reason))
    }
}

extension SendRequestError : LocalizedError {
    var localizedDescription: String {
        return reason ?? ""
    }
}

protocol NetworkSessionProtocol {
    typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void
    func makeRequest(_ request: URLRequest, completionHandler: @escaping CompletionHandler)
}

extension URLSession : NetworkSessionProtocol {
    func makeRequest(_ request: URLRequest, completionHandler: @escaping CompletionHandler) {
        let task = dataTask(with: request) { (data, response, error) in
            completionHandler(data, response, error)
        }
        task.resume()
    }
}

struct NetworkHelper {
    static func sendRequest(_ request: URLRequest, usingSession networkSession: NetworkSessionProtocol) -> Future<SendRequestValue>  {
        let promise = Promise<SendRequestValue>()
        
        networkSession.makeRequest(request) { (data, response, error) in
            let result = createResultFromNetworkResponse(data: data, response: response, error: error)
            switch (result) {
            case .value(let value):
                promise.resolve(with: value)
            case .error(let error):
                promise.reject(with: error)
            }
        }
            
        return promise
    }
    
    static func createResultFromNetworkResponse(data: Data?, response: URLResponse?, error: Error?) -> Result<SendRequestValue> {
        if let error = error {
            return .error(SendRequestError(reason: "\(error.localizedDescription)", data: data))
        }
        guard let response = response as? HTTPURLResponse else {
            return .error(SendRequestError(reason: "No response", data: nil))
        }
        
        let responseCode = response.statusCode
        
        let json: Any?
        var jsonError: Error? = nil
        
        if let data = data, data.count > 0 {
            do {
                json = try JSONSerialization.jsonObject(with: data, options: [])
            } catch let error {
                jsonError = error
                json = nil
            }
        } else {
            json = nil
        }
        
        if responseCode == 401 {
            return .error(SendRequestError(reason: "Invalid API Key", data: data))
        } else if responseCode >= 400 {
            var reason = "Invalid Request"
            if let jsonDict = json as? [AnyHashable : Any], let msgFromDict = jsonDict["msg"] as? String {
                reason = msgFromDict
            } else if responseCode >= 500 {
                reason = "Internal Server Error"
            }
            return .error(SendRequestError(reason: reason, data: data))
        } else if responseCode == 200 {
            if let data = data, data.count > 0 {
                if let jsonError = jsonError {
                    var reason = "Could not parse json, error: \(jsonError.localizedDescription)"
                    if let stringValue = String(data: data, encoding: .utf8) {
                        reason = "Could not parse json: \(stringValue), error: \(jsonError.localizedDescription)"
                    }
                    return .error(SendRequestError(reason: reason, data: data))
                } else if let json = json as? [AnyHashable : Any] {
                    return .value(json)
                } else {
                    return .error(SendRequestError(reason: "Response is not a dictionary", data: data))
                }
            } else {
                return .error(SendRequestError(reason: "No data received", data: data))
            }
        } else {
            return .error(SendRequestError(reason: "Received non-200 response: \(responseCode)", data: data))
        }
    }
}
