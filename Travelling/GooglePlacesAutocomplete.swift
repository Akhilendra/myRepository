//
//  GooglePlacesAutocomplete.swift
//  GooglePlacesAutocomplete
//
//  Created by Howard Wilson on 10/02/2015.
//  Copyright (c) 2015 Howard Wilson. All rights reserved.
//

import UIKit

public let ErrorDomain2: String! = "GooglePlacesAutocompleteErrorDomain"

public struct LocationBias {
  public let latitude: Double
  public let longitude: Double
  public let radius: Int
  
  public init(latitude: Double = 0, longitude: Double = 0, radius: Int = 2000000000) {
    self.latitude = latitude
    self.longitude = longitude
    self.radius = radius
  }
  
  public var location: String {
    return "\(latitude),\(longitude)"
  }
}

public enum PlaceType: CustomStringConvertible {
  case All
  case Geocode
  case Address
  case Establishment
  case Regions
  case Cities

  public var description : String {
    switch self {
      case .All: return ""
      case .Geocode: return "geocode"
      case .Address: return "address"
      case .Establishment: return "establishment"
      case .Regions: return "(regions)"
      case .Cities: return "(cities)"
    }
  }
}

public class Place: NSObject {
  public let id: String
  public let desc: String
  public var apiKey: String?

  override public var description: String {
    get { return desc }
  }

  public init(id: String, description: String) {
    self.id = id
    self.desc = description
  }

  public convenience init(prediction: [String: AnyObject], apiKey: String?) {
    self.init(
      id: prediction["place_id"] as! String,
      description: prediction["description"] as! String
    )

    self.apiKey = apiKey
  }

  /**
    Call Google Place Details API to get detailed information for this place
  
    Requires that Place#apiKey be set
  
    - parameter result: Callback on successful completion with detailed place information
  */
  public func getDetails(result: PlaceDetails -> ()) {
    GooglePlaceDetailsRequest(place: self).request(result)
  }
}

public class PlaceDetails: CustomStringConvertible {
  public let name: String
  public let latitude: Double
  public let longitude: Double
  public let raw: [String: AnyObject]
    
  //public let long_name: String

  public init(json: [String: AnyObject]) {
    let result = json["result"] as! [String: AnyObject]
    let geometry = result["geometry"] as! [String: AnyObject]
    let location = geometry["location"] as! [String: AnyObject]
    
    //mycode
    //let shortName = json["result"]["address_components"]["shortName"]
    //let longName = json["result"]["formatted_address"]
    //self.long_name = result["address_components"]!["formatted_address"] as! String
    //end my code

    self.name = result["name"] as! String
    self.latitude = location["lat"] as! Double
    self.longitude = location["lng"] as! Double
    self.raw = json
    
    //print("this is raw: \(raw)")
  }

  public var description: String {
    return "PlaceDetails: \(name) (\(latitude), \(longitude))"
  }
}

@objc public protocol GooglePlacesAutocompleteDelegate {
  optional func placesFound(places: [Place])
  optional func placeSelected(place: Place)
  optional func historyPlaceSelected(title: String , lat: Double , lon: Double)
  optional func placeViewClosed()
}

// MARK: - GooglePlacesAutocomplete
public class GooglePlacesAutocomplete: UINavigationController {
  public var gpaViewController: GooglePlacesAutocompleteContainer!
  public var closeButton: UIBarButtonItem!

  // Proxy access to container navigationItem
  public override var navigationItem: UINavigationItem {
    get { return gpaViewController.navigationItem }
  }

  public var placeDelegate: GooglePlacesAutocompleteDelegate? {
    get { return gpaViewController.delegate }
    set { gpaViewController.delegate = newValue }
  }
  
  public var locationBias: LocationBias? {
    get { return gpaViewController.locationBias }
    set { gpaViewController.locationBias = newValue }
  }

  public convenience init(apiKey: String, placeType: PlaceType = .All) {
    let gpaViewController = GooglePlacesAutocompleteContainer(
      apiKey: apiKey,
      placeType: placeType
    )

    self.init(rootViewController: gpaViewController)
    self.gpaViewController = gpaViewController

    closeButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.Stop, target: self, action: #selector(GooglePlacesAutocomplete.close))
    closeButton.style = UIBarButtonItemStyle.Done

    gpaViewController.navigationItem.leftBarButtonItem = closeButton
    gpaViewController.navigationItem.title = "Enter Address"
  }

  func close() {
    placeDelegate?.placeViewClosed?()
  }

  public func reset() {
    gpaViewController.searchBar.text = ""
    gpaViewController.searchBar(gpaViewController.searchBar, textDidChange: "")
  }
}

// MARK: - GooglePlacesAutocompleteContainer
public class GooglePlacesAutocompleteContainer: UIViewController {
  @IBOutlet public weak var searchBar: UISearchBar!
  @IBOutlet weak var tableView: UITableView!
  @IBOutlet weak var historyTableView: UITableView!
  @IBOutlet weak var topConstraint: NSLayoutConstraint!

  var delegate: GooglePlacesAutocompleteDelegate?
  var apiKey: String?
  var places = [Place]()
  var placeType: PlaceType = .All
  var locationBias: LocationBias?
    
  var placesTitleArray = [String]()
  var placesDescriptionArray = [String]()
  var placesLatArray = [Double]()
  var placesLonArray = [Double]()

  convenience init(apiKey: String, placeType: PlaceType = .All) {
    let bundle = NSBundle(forClass: GooglePlacesAutocompleteContainer.self)

    self.init(nibName: "GooglePlacesAutocomplete", bundle: bundle)
    self.apiKey = apiKey
    self.placeType = placeType
  }

  deinit {
    NSNotificationCenter.defaultCenter().removeObserver(self)
  }

  override public func viewWillLayoutSubviews() {
    topConstraint.constant = topLayoutGuide.length
  }

  override public func viewDidLoad() {
    super.viewDidLoad()

    NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(GooglePlacesAutocompleteContainer.keyboardWasShown(_:)), name: UIKeyboardDidShowNotification, object: nil)
    NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(GooglePlacesAutocompleteContainer.keyboardWillBeHidden(_:)), name: UIKeyboardWillHideNotification, object: nil)

    searchBar.becomeFirstResponder()
    tableView.registerClass(GooglePlaceTVCell.self, forCellReuseIdentifier: "Cell")
    historyTableView.registerClass(GooglePlaceTVCell.self, forCellReuseIdentifier: "historyCell")
    //historyTableView.reloadData()
    
    //self.searchBar.layer.borderColor = UIColor.blueColor().CGColor
    //self.searchBar.layer.borderWidth = 1
    self.searchBar.backgroundColor = UIColor.clearColor()
    self.searchBar.placeholder = "Enter location"
    self.searchBar.layer.cornerRadius = 0.0
    self.searchBar.clipsToBounds = true
    //self.searchBar.barStyle = UIBarStyle.BlackTranslucent
    self.searchBar.searchBarStyle = UISearchBarStyle.Minimal
    self.searchBar.sizeToFit()
    let image = UIImage(named: "navigation-red_35")
    self.searchBar.setImage(image, forSearchBarIcon: UISearchBarIcon.Search, state: UIControlState.Normal)
    //self.searchBar.setImage(image, forSearchBarIcon: UISearchBarIcon.Clear, state: UIControlState.Normal)
    
    //get places history
    let defaults = NSUserDefaults.standardUserDefaults()
    placesTitleArray = defaults.objectForKey(TravellingConstants.NSUserDefaults.placeTitleArray) as? [String] ?? [String]()
    placesTitleArray = placesTitleArray.reverse()
    placesDescriptionArray = defaults.objectForKey(TravellingConstants.NSUserDefaults.placeDetailArray) as? [String] ?? [String]()
    placesDescriptionArray = placesDescriptionArray.reverse()
    placesLatArray = defaults.objectForKey(TravellingConstants.NSUserDefaults.placeLatArray) as? [Double] ?? [Double]()
    placesLonArray = defaults.objectForKey(TravellingConstants.NSUserDefaults.placeLonArray) as? [Double] ?? [Double]()
//    for _ in 0...20 {
//        placesDescriptionArray.append("Not Available")
//    }
//    defaults.synchronize()
    //print("print from googlePlaces: \(defaults.objectForKey(TravellingConstants.NSUserDefaults.placeDetailArray))")
  }

  func keyboardWasShown(notification: NSNotification) {
    if isViewLoaded() && view.window != nil {
      let info: Dictionary = notification.userInfo!
      let keyboardSize: CGSize = (info[UIKeyboardFrameBeginUserInfoKey]?.CGRectValue.size)!
      let contentInsets = UIEdgeInsetsMake(0.0, 0.0, keyboardSize.height, 0.0)

      tableView.contentInset = contentInsets;
      tableView.scrollIndicatorInsets = contentInsets;
    }
  }

  func keyboardWillBeHidden(notification: NSNotification) {
    if isViewLoaded() && view.window != nil {
      self.tableView.contentInset = UIEdgeInsetsZero
      self.tableView.scrollIndicatorInsets = UIEdgeInsetsZero
    }
  }
}

// MARK: - GooglePlacesAutocompleteContainer (UITableViewDataSource / UITableViewDelegate)
extension GooglePlacesAutocompleteContainer: UITableViewDataSource, UITableViewDelegate {
  public func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    if tableView == self.tableView {
        return places.count
    } else {
        //return placesTitleArray.count
        return 10
    }
  }

  public func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
    if tableView == self.tableView {
        //let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath) as! GooglePlaceTVCell
        let cell: UITableViewCell = UITableViewCell(style: UITableViewCellStyle.Subtitle, reuseIdentifier: "Cell")
        
        let place = self.places[indexPath.row]
        let shortPlace = place.description.componentsSeparatedByString(",")
        // Configure the cell
        cell.textLabel!.text = shortPlace[0]
        cell.detailTextLabel?.text = place.description
        //cell.imageView?.image = UIImage(named: "navigation-red_25")
        cell.imageView?.image = UIImage(named: "marker_20")
        cell.detailTextLabel?.textColor = UIColor.darkGrayColor()
        cell.accessoryType = UITableViewCellAccessoryType.DisclosureIndicator
        //cell.textLabel?.font = UIFont.systemFontOfSize(10)
        return cell
    } else {
        //let cell = tableView.dequeueReusableCellWithIdentifier("historyCell", forIndexPath: indexPath) as! GooglePlaceTVCell
         let cell: UITableViewCell = UITableViewCell(style: UITableViewCellStyle.Subtitle, reuseIdentifier: "historyCell")
        // Configure the cell
        cell.textLabel!.text = placesTitleArray[indexPath.row]
        cell.detailTextLabel?.text = placesDescriptionArray[indexPath.row]
        cell.accessoryType = UITableViewCellAccessoryType.DisclosureIndicator
        //cell.imageView?.image = UIImage(named: "navigation-red_25")
        cell.imageView?.image = UIImage(named: "marker_20")
        cell.detailTextLabel?.textColor = UIColor.darkGrayColor()
        return cell
    }
  }

  public func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
    
    if tableView == self.tableView {
        //self.dismissViewControllerAnimated(true, completion: nil)
        
        delegate?.placeSelected?(self.places[indexPath.row])
        delegate?.placeViewClosed!()
        
        let defaults = NSUserDefaults.standardUserDefaults()
        var placesDescriptionArray = defaults.objectForKey(TravellingConstants.NSUserDefaults.placeDetailArray) as? [String] ?? [String]()
        placesDescriptionArray.append(places[indexPath.row].description)
        defaults.setObject(placesDescriptionArray, forKey: TravellingConstants.NSUserDefaults.placeDetailArray)
    } else {
        delegate?.historyPlaceSelected!(placesTitleArray[indexPath.row], lat: placesLatArray[indexPath.row], lon: placesLonArray[indexPath.row])
        delegate?.placeViewClosed!()
    }
  }
    
    public func tableView(tableView: UITableView, willDisplayCell cell: UITableViewCell, forRowAtIndexPath indexPath: NSIndexPath) {
        let kSeparatorTag = 123
        let kSeparatorHeight: CGFloat = 1.5
        if cell.viewWithTag(kSeparatorTag) == nil //add separator only once
        {
            let separatorView = UIView(frame: CGRectMake(0, cell.frame.height - kSeparatorHeight, cell.frame.width, kSeparatorHeight))
            //separatorView.tag = kSeparatorId
            separatorView.backgroundColor = UIColor.lightGrayColor()
            separatorView.autoresizingMask = [.FlexibleWidth, .FlexibleHeight]
            
            cell.addSubview(separatorView)
        }
    }
}

// MARK: - GooglePlacesAutocompleteContainer (UISearchBarDelegate)
extension GooglePlacesAutocompleteContainer: UISearchBarDelegate {
  public func searchBar(searchBar: UISearchBar, textDidChange searchText: String) {
    if (searchText == "") {
      self.places = []
      tableView.hidden = true
    } else {
      getPlaces(searchText)
    }
  }

  /**
    Call the Google Places API and update the view with results.

    - parameter searchString: The search query
  */
  
  private func getPlaces(searchString: String) {
    var params = [
      "input": searchString,
      "types": placeType.description,
      "key": apiKey ?? ""
    ]
    
    if let bias = locationBias {
      params["location"] = bias.location
      params["radius"] = bias.radius.description
    }
    
    if (searchString == ""){
      return
    }
    
    GooglePlacesRequestHelpers.doRequest(
      "https://maps.googleapis.com/maps/api/place/autocomplete/json",
      params: params
      ) { json, error in
        if let json = json{
          if let predictions = json["predictions"] as? Array<[String: AnyObject]> {
            self.places = predictions.map { (prediction: [String: AnyObject]) -> Place in
              return Place(prediction: prediction, apiKey: self.apiKey)
            }
          self.tableView.reloadData()
          self.tableView.hidden = false
          self.delegate?.placesFound?(self.places)
        }
      }
    }
  }
}

// MARK: - GooglePlaceDetailsRequest
class GooglePlaceDetailsRequest {
  let place: Place

  init(place: Place) {
    self.place = place
  }

  func request(result: PlaceDetails -> ()) {
    GooglePlacesRequestHelpers.doRequest(
      "https://maps.googleapis.com/maps/api/place/details/json",
      params: [
        "placeid": place.id,
        "key": place.apiKey ?? ""
      ]
    ) { json, error in
      if let json = json as? [String: AnyObject] {
        result(PlaceDetails(json: json))
      }
      if let error = error {
        // TODO: We should probably pass back details of the error
        print("Error fetching google place details: \(error)")
      }
    }
  }
}

// MARK: - GooglePlacesRequestHelpers
class GooglePlacesRequestHelpers {
  /**
  Build a query string from a dictionary

  - parameter parameters: Dictionary of query string parameters
  - returns: The properly escaped query string
  */
  private class func query(parameters: [String: AnyObject]) -> String {
    var components: [(String, String)] = []
    for key in Array(parameters.keys).sort(<) {
      let value: AnyObject! = parameters[key]
      components += [(escape(key), escape("\(value)"))]
    }

    return (components.map{"\($0)=\($1)"} as [String]).joinWithSeparator("&")
  }

  private class func escape(string: String) -> String {
    let legalURLCharactersToBeEscaped: CFStringRef = ":/?&=;+!@#$()',*"
    return CFURLCreateStringByAddingPercentEscapes(nil, string, nil, legalURLCharactersToBeEscaped, CFStringBuiltInEncodings.UTF8.rawValue) as String
  }

  private class func doRequest(url: String, params: [String: String], completion: (NSDictionary?,NSError?) -> ()) {
    let request = NSMutableURLRequest(
      URL: NSURL(string: "\(url)?\(query(params))")!
    )

    let session = NSURLSession.sharedSession()
    let task = session.dataTaskWithRequest(request) { data, response, error in
      self.handleResponse(data, response: response as? NSHTTPURLResponse, error: error, completion: completion)
    }

    task.resume()
  }

  private class func handleResponse(data: NSData!, response: NSHTTPURLResponse!, error: NSError!, completion: (NSDictionary?, NSError?) -> ()) {
    
    // Always return on the main thread...
    let done: ((NSDictionary?, NSError?) -> Void) = {(json, error) in
        dispatch_async(dispatch_get_main_queue(), {
            UIApplication.sharedApplication().networkActivityIndicatorVisible = false
            completion(json,error)
        })
    }
    
    if let error = error {
      print("GooglePlaces Error: \(error.localizedDescription)")
      done(nil,error)
      return
    }

    if response == nil {
      print("GooglePlaces Error: No response from API")
      let error = NSError(domain: ErrorDomain, code: 1001, userInfo: [NSLocalizedDescriptionKey:"No response from API"])
      done(nil,error)
      return
    }

    if response.statusCode != 200 {
      print("GooglePlaces Error: Invalid status code \(response.statusCode) from API")
      let error = NSError(domain: ErrorDomain, code: response.statusCode, userInfo: [NSLocalizedDescriptionKey:"Invalid status code"])
      done(nil,error)
      return
    }
    
    let json: NSDictionary?
    do {
      json = try NSJSONSerialization.JSONObjectWithData(
        data,
        options: NSJSONReadingOptions.MutableContainers) as? NSDictionary
    } catch {
      print("Serialisation error")
      let serialisationError = NSError(domain: ErrorDomain, code: 1002, userInfo: [NSLocalizedDescriptionKey:"Serialization error"])
      done(nil,serialisationError)
      return
    }

    if let status = json?["status"] as? String {
      if status != "OK" {
        print("GooglePlaces API Error: \(status)")
        let error = NSError(domain: ErrorDomain, code: 1002, userInfo: [NSLocalizedDescriptionKey:status])
        done(nil,error)
        return
      }
    }
    
    done(json,nil)

  }
}
