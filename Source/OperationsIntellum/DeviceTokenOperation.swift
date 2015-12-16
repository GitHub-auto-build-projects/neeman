import Foundation
import KeychainAccess

public class DeviceTokenOperation: GroupOperation {
    let authCookieName = Settings.sharedInstance.authCookieName

    // MARK: Properties
    private let deviceToken: String
    private let finishHandler: ((Operation, [NSError]) -> Void)?
    let errorDomain = "DeviceTokenErrorDomain"
    let urlString = "http://intellum.level.openlms.com/user.json"
    let keychain = Settings.sharedInstance.keychain
    
    // MARK: Initialization
    
    /// - parameter cacheFile: The file `NSURL` to which the earthquake feed will be downloaded.
    public init(deviceToken: String, finishHandler: ((Operation, [NSError]) -> Void)? = nil) {
        self.deviceToken = deviceToken
        self.finishHandler = finishHandler
        
        super.init(operations: [])
        name = "DeviceToken"
        
        guard let _ = keychain["app_auth_cookie"] else {
            let error =  NSError(domain: self.errorDomain, code: 1, userInfo: [:])
            cancelWithError(error)
            return
        }

        let url = NSURL(string: urlString)!
        let request = requestWithURL(url)
        
        let params = ["user": ["device_token":deviceToken]]
        
        do {
            try request.HTTPBody = NSJSONSerialization.dataWithJSONObject(params, options: NSJSONWritingOptions(rawValue: 0))
        } catch {}
        
        let task = NSURLSession.sharedSession().dataTaskWithRequest(request) { (data: NSData?, response: NSURLResponse?, error: NSError?) -> Void in
            let parseDataOperation = NSBlockOperation { () -> Void in
                self.downloadFinished(data, response: response as? NSHTTPURLResponse, error: error)
            }
            self.addOperation(parseDataOperation)
        }
        
        let taskOperation = URLSessionTaskOperation(task: task)
        
        let reachabilityCondition = ReachabilityCondition(host: url)
        taskOperation.addCondition(reachabilityCondition)
        
        let networkObserver = NetworkObserver()
        taskOperation.addObserver(networkObserver)
        
        addOperation(taskOperation)
    }
    
    func requestWithURL(url: NSURL) -> NSMutableURLRequest {

        let request = NSMutableURLRequest(URL: url, cachePolicy: .UseProtocolCachePolicy, timeoutInterval: 10)
        
        request.addValue("application/json", forHTTPHeaderField:"Content-Type")
        request.addValue("application/json", forHTTPHeaderField:"Accept")
        
        request.HTTPMethod = "PUT"
        
        if let authToken = keychain["app_auth_cookie"] {
            let authCookie = "\(authCookieName)=\(authToken);"
            request.setValue(authCookie, forHTTPHeaderField: "Cookie")
        }

        return request
    }
    
    func downloadFinished(data: NSData?, response: NSHTTPURLResponse?, error: NSError?) {
        if let localData = data {
            do {
                let statusCode = response?.statusCode ?? 0
                var errors: [NSError] = []
                if case 200...299 = statusCode {
                    if let jsonObj = try NSJSONSerialization.JSONObjectWithData(
                        localData,
                        options: NSJSONReadingOptions(rawValue:0)) as? Dictionary<String, AnyObject> {
                        print(jsonObj)
                    }
                } else if response?.statusCode == 401 {
                    let error =  NSError(domain: self.errorDomain, code: 1, userInfo: [:])
                    errors.append(error)
                } else {
                    let error =  NSError(domain: self.errorDomain, code: 2, userInfo: [:])
                    errors.append(error)
                }
                finish(errors)
                self.finishHandler?(self, errors)
            } catch let error as NSError {
                self.finishHandler?(self, [error])
                aggregateError(error)
            }
            
        } else if let error = error {
            aggregateError(error)
            self.finishHandler?(self, [error])
        } else {
            // Do nothing, and the operation will automatically finish.
        }
    }
}
