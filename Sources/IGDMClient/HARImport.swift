import Foundation

enum HARImportError: LocalizedError {
    case noSendMutation
    case invalidVariables

    var errorDescription: String? {
        switch self {
        case .noSendMutation:
            return "No successful IGDirectTextSendMutation request was found in that HAR."
        case .invalidVariables:
            return "The HAR send request did not contain readable GraphQL variables."
        }
    }
}

struct HARImporter {
    func importSendTemplate(from data: Data) throws -> GraphQLSendTemplate {
        let har = try JSONDecoder().decode(HARFile.self, from: data)

        guard let entry = har.log.entries.first(where: { entry in
            entry.request.url.contains("/api/graphql") &&
                entry.request.method.uppercased() == "POST" &&
                entry.response.status == 200 &&
                entry.request.postData?.params.contains(where: {
                    $0.name == "fb_api_req_friendly_name" &&
                        decoded($0.value) == "IGDirectTextSendMutation"
                }) == true
        }) else {
            throw HARImportError.noSendMutation
        }

        var formFields = (entry.request.postData?.params ?? []).reduce(into: [String: String]()) { result, param in
            result[param.name] = decoded(param.value)
        }

        guard let variables = formFields["variables"],
              variables.contains("sensitive_string_value") else {
            throw HARImportError.invalidVariables
        }

        formFields["variables"] = variables

        let headers = entry.request.headers.reduce(into: [String: String]()) { result, header in
            result[header.name.lowercased()] = header.value
        }

        return GraphQLSendTemplate(
            formFields: formFields,
            headers: headers,
            sourceURL: entry.request.url
        )
    }

    private func decoded(_ value: String) -> String {
        var previous = value

        for _ in 0..<3 {
            guard let next = previous.removingPercentEncoding,
                  next != previous else {
                return previous
            }

            previous = next
        }

        return previous
    }
}

private struct HARFile: Decodable {
    var log: HARLog
}

private struct HARLog: Decodable {
    var entries: [HAREntry]
}

private struct HAREntry: Decodable {
    var request: HARRequest
    var response: HARResponse
}

private struct HARRequest: Decodable {
    var method: String
    var url: String
    var headers: [HARNameValue]
    var postData: HARPostData?
}

private struct HARResponse: Decodable {
    var status: Int
}

private struct HARPostData: Decodable {
    var params: [HARNameValue]
}

private struct HARNameValue: Decodable {
    var name: String
    var value: String
}
