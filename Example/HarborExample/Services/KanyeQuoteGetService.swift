//
//  KanyeQuoteGetService.swift
//  HarborExample
//
//  Created by Javier Manzo on 21/02/2023.
//

import Foundation
import Harbor

struct MovieResponseModel: Codable {
    let movies: [MovieModel]
    let totalResults: String

    enum CodingKeys: String, CodingKey {
         case movies = "Search"
         case totalResults = "totalResults"
     }
}

struct MovieModel: Codable, Identifiable {
    let id: String
    let title: String
    let year: String
    let type: String
    let posterUrl: String

    enum CodingKeys: String, CodingKey {
         case id = "imdbID"
         case title = "Title"
         case year = "Year"
         case type = "Type"
         case posterUrl = "Poster"
     }
}


class KanyeQuoteGetService: HServiceProtocolWithResult {
    typealias T = MovieResponseModel

    var url: String = "https://www.omdbapi.com/"

    var httpMethod: HHttpMethod = .get

    var headers: [String : String]?

    var queryParameters: [String : String]? = [:]

    var pathParameters: [String : String]? = nil

    var body: [String : Any]? = nil

    var needAuth: Bool = false

    var timeout: TimeInterval = 5

    init() {
        queryParameters?["s"] = "Batman"
        queryParameters?["page"] = "1"
        queryParameters?["apikey"] = "433923b9"
    }
}
