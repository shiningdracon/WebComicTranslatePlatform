import Foundation

protocol UtilitiesProtocol {
    func ChineseConvertS2T(_ s: String) -> String
    func ChineseConvertT2S(_ t: String) -> String
    func BBCode2HTML(bbcode: String, local: i18nLocale) throws -> String
}

public enum WebFrameworkError: Error {
    case RuntimeError(String)
    case BBCodeError(String)
}

public struct SessionInfo {
    var remoteAddress: String
    var locale: i18nLocale
}

public enum SiteResponseStatus {
    case Error(message: String)
    case OK(view: String, data: [String: Any])
    case Redirect(location: String)
    case NotFound
}

public struct SiteResponse {
    var status: SiteResponseStatus
    var session: SessionInfo?
}

public final class SiteController {
    let utilities: UtilitiesProtocol
    let dataManager: DataManager

    init(util: UtilitiesProtocol, data: DataManager) {
        self.utilities = util
        self.dataManager = data
    }

    func i18n(_ ori: String, locale: i18nLocale?) -> String {
        if locale != nil {
            switch locale! {
            case .zh_CN:
                return utilities.ChineseConvertT2S(ori)
            case .zh_TW:
                return utilities.ChineseConvertS2T(ori)
            }
        } else {
            return ori
        }
    }

    func formatTime(time: Double, timezone: Int, daySavingTime: Int) -> String {
        let date: Date = Date(timeIntervalSince1970: time)
        let diff = Double((timezone + daySavingTime) * 3600)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd hh:mm:ss"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: Int(diff))

        return dateFormatter.string(from: date)
    }

    func reGenerateJSON(jsonString: String) -> String? {
        do {
            if let jsonData = jsonString.data(using: .utf8, allowLossyConversion: false) {
                if let jsonDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

                    let jsonDataValidated = try JSONSerialization.data(withJSONObject: jsonDict)

                    if let jsonString = String(data: jsonDataValidated, encoding: .utf8) {
                        return jsonString
                    }
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    // handlers
    public func main(session: SessionInfo, page: UInt32) -> SiteResponse {
        let data: [String: Any] = ["lang": ComicI18n.instance.getI18n(session.locale)]
        return SiteResponse(status: .OK(view: "main.mustache", data: data), session: session)
    }

    public func viewPage(session: SessionInfo, comicId: UInt32, pageIndex: UInt32) -> SiteResponse {
        do {
            if let comic = try self.dataManager.getComic(id: comicId) {
                var data: [String: Any] = ["lang": ComicI18n.instance.getI18n(session.locale)]
                data["comic_id"] = comicId
                if pageIndex > 0 && pageIndex <= comic.pageCount {
                    if let page = try self.dataManager.getPage(comicId: comicId, pageIndex: pageIndex) {
                        data["page_title"] = "《\(i18n(comic.title, locale: session.locale))》\(i18n(page.title, locale: session.locale)) / \(pageIndex)"
                        data["page_index"] = pageIndex
                        if pageIndex > 1 {
                            data["previous_page_index"] = ["index": pageIndex - 1]
                        }
                        if pageIndex < comic.pageCount {
                            data["next_page_index"] = ["index": pageIndex + 1]
                        }
                        var jumpArray: Array<[String: Any]> = Array(1...comic.pageCount).map({ ["index": $0 as Any] })
                        jumpArray[Int(pageIndex-1)]["selected"] = "selected"
                        data["quick_jump"] = jumpArray
                        data["title"] = i18n(page.title, locale: session.locale)
                        data["description"] = i18n(try utilities.BBCode2HTML(bbcode: page.description, local: session.locale), locale: session.locale)
                        data["content"] = i18n(page.content, locale: session.locale)
                        return SiteResponse(status: .OK(view: "viewpage.mustache", data: data), session: session)
                    }
                }
            }
            return SiteResponse(status: .NotFound, session: session)
        } catch {
            return SiteResponse(status: .Error(message: "DB failed"), session: session)
        }
    }

    public func viewLastPage(session: SessionInfo, comicId: UInt32) -> SiteResponse {
        return SiteResponse(status: .OK(view: "viewlastpage.mustache", data: [:]), session: session)
    }

    public func editPage(session: SessionInfo, comicId: UInt32, pageIndex: UInt32) -> SiteResponse {
        do {
            if let page = try self.dataManager.getPage(comicId: comicId, pageIndex: pageIndex) {
                var data: [String: Any] = ["lang": ComicI18n.instance.getI18n(session.locale)]
                data["comic_id"] = comicId
                data["page_index"] = pageIndex
                data["title"] = page.title
                data["description"] = page.description.stringByEncodingHTML_NoConvertCRLF
                data["content"] = page.content
                return SiteResponse(status: .OK(view: "editpage.mustache", data: data), session: session)
            }
            return SiteResponse(status: .NotFound, session: session)
        } catch {
            return SiteResponse(status: .Error(message: "DB failed"), session: session)
        }
    }

    public func addPage(session: SessionInfo, comicId: UInt32) -> SiteResponse {
        do {
            guard let _ = try self.dataManager.getComic(id: comicId) else {
                return SiteResponse(status: .NotFound, session: session)
            }
            var data: [String: Any] = ["lang": ComicI18n.instance.getI18n(session.locale)]
            data["comic_id"] = comicId
            return SiteResponse(status: .OK(view: "addpage.mustache", data: data), session: session)
        } catch {
            return SiteResponse(status: .Error(message: "DB failed"), session: session)
        }
    }

    public func postAddPage(session: SessionInfo, comicId: UInt32, title: String, description: String, imgWebURL: String, onSeccuss: ((_ pageId: UInt32) throws -> Void)) -> SiteResponse {

        do {
            self.dataManager.transactionStart()

            guard let comic = try self.dataManager.getComic(id: comicId) else {
                return SiteResponse(status: .NotFound, session: session)
            }
            _ = try self.utilities.BBCode2HTML(bbcode: description, local: session.locale)

            let pageIndex = comic.pageCount + 1
            let pageId = try self.dataManager.addPage(comicId: comicId, pageIndex: pageIndex, title: title, poster: "guest", description: description, content: "{\"backgroundImage\":{\"type\":\"image\",\"originX\":\"left\",\"originY\":\"top\",\"left\":0,\"top\":0,\"fill\":\"rgb(0,0,0)\",\"stroke\":null,\"strokeWidth\":0,\"strokeDashArray\":null,\"strokeLineCap\":\"butt\",\"strokeLineJoin\":\"miter\",\"strokeMiterLimit\":10,\"scaleX\":1,\"scaleY\":1,\"angle\":0,\"flipX\":false,\"flipY\":false,\"opacity\":1,\"shadow\":null,\"visible\":true,\"clipTo\":null,\"backgroundColor\":\"\",\"fillRule\":\"nonzero\",\"globalCompositeOperation\":\"source-over\",\"transformMatrix\":null,\"skewX\":0,\"skewY\":0,\"crossOrigin\":\"\",\"alignX\":\"none\",\"alignY\":\"none\",\"meetOrSlice\":\"meet\",\"src\":\"\(imgWebURL)\",\"filters\":[]}}")

            guard self.dataManager.updateComic(id: comicId, title: comic.title, author: comic.author, pageCount: pageIndex, description: comic.description) else {
                self.dataManager.transactionRollback()
                return SiteResponse(status: .Error(message: "DB failed"), session: session)
            }

            try onSeccuss(pageId)

            self.dataManager.transactionCommit()

            return SiteResponse(status: .Redirect(location: "/comic/\(comicId)/page/\(pageIndex)/edit"), session: session)
        } catch WebFrameworkError.RuntimeError(let msg) {
            self.dataManager.transactionRollback()
            return SiteResponse(status: .Error(message: msg), session: session)
        } catch WebFrameworkError.BBCodeError(let detail) {
            self.dataManager.transactionRollback()
            var data: [String: Any] = ["lang": ComicI18n.instance.getI18n(session.locale)]
            data["comic_id"] = comicId
            data["title"] = title
            data["description"] = description.stringByEncodingHTML_NoConvertCRLF
            data["error"] = detail
            return SiteResponse(status: .OK(view: "addpage.mustache", data: data), session: session)
        } catch {
            self.dataManager.transactionRollback()
            return SiteResponse(status: .Error(message: "DB failed"), session: session)
        }
    }

    public func postUpdatePage(session: SessionInfo, comicId: UInt32, pageIndex: UInt32, title: String, description: String, content: String) -> SiteResponse {
        if let jsonString = reGenerateJSON(jsonString: content) {
            do {
                _ = try self.utilities.BBCode2HTML(bbcode: description, local: session.locale)
            } catch WebFrameworkError.BBCodeError(let detail) {
                var data: [String: Any] = ["lang": ComicI18n.instance.getI18n(session.locale)]
                data["comic_id"] = comicId
                data["page_index"] = pageIndex
                data["title"] = title
                data["description"] = description.stringByEncodingHTML_NoConvertCRLF
                data["content"] = content
                data["error"] = detail
                return SiteResponse(status: .OK(view: "editpage.mustache", data: data), session: session)
            } catch { //TODO: find out which exception or swift bug
                return SiteResponse(status: .Error(message: "Unknow BBCode error"), session: session)
            }
            if self.dataManager.updatePage(comicId: comicId, pageIndex: pageIndex, title: title, description: description, content: jsonString) {
                return SiteResponse(status: .Redirect(location: "/comic/\(comicId)/page/\(pageIndex)"), session: session)
            } else {
                return SiteResponse(status: .Error(message: "update failed"), session: session)
            }
        } else {
            return SiteResponse(status: .Error(message: "Invalid JSON"), session: session)
        }
    }

    public func viewComicList(session: SessionInfo, page: UInt32) -> SiteResponse {
        let display: UInt32 = 25 //TODO: make display configurable
        let offset: UInt32 = (page <= 1 ? 0 : page - 1) * display

        do {
            var data: [String: Any] = ["lang": ComicI18n.instance.getI18n(session.locale)]
            data["page_title"] = "" //TODO:
            if let comicList = try self.dataManager.getComicList(offset: offset, limit: display), comicList.count > 0 {
                var dataComicList: Array<[String: Any]> = []
                for comic in comicList {
                    var dataComic: [String: Any] = [:]
                    dataComic["id"] = comic.id
                    dataComic["title"] = i18n(comic.title, locale: session.locale)
                    dataComic["poster"] = comic.poster
                    dataComic["description"] = i18n(try utilities.BBCode2HTML(bbcode: page.description, local: session.locale), locale: session.locale)
                    dataComic["page_count"] = comic.pageCount
                    dataComicList.append(dataComic)
                }
                data["comic_list"] = dataComicList
            }
            // if comic_list is not set, means no comic right now
            return SiteResponse(status: .OK(view: "viewcomiclist.mustache", data: data), session: session)
        } catch WebFrameworkError.BBCodeError(let msg) {
            return SiteResponse(status: .Error(message: msg), session: session)
        } catch {
            return SiteResponse(status: .Error(message: "DB failed"), session: session)
        }
    }

    public func viewComic(session: SessionInfo, comicId: UInt32) -> SiteResponse {
        do {
            if let comic = try self.dataManager.getComic(id: comicId) {
                var data: [String: Any] = ["lang": ComicI18n.instance.getI18n(session.locale)]
                data["page_title"] = "《\(i18n(comic.title, locale: session.locale))》"
                data["comic_id"] = comic.id
                data["title"] = i18n(comic.title, locale: session.locale)
                data["author"] = comic.author
                data["poster"] = comic.poster
                data["description"] = i18n(try utilities.BBCode2HTML(bbcode: comic.description, local: session.locale), locale: session.locale)

                data["page_count"] = comic.pageCount
                if let pageList = try self.dataManager.getPageListOfComic(id: comicId), pageList.count > 0 {
                    var dataPageList: Array<[String: Any]> = []
                    for page in pageList {
                        var dataPage: [String: Any] = [:]
                        dataPage["index"] = page.index
                        dataPage["title"] = page.title
                        dataPageList.append(dataPage)
                    }
                    data["page_list"] = dataPageList

                    var sliceOffset = dataPageList.count - 5
                    if sliceOffset < 0 {
                        sliceOffset = 0
                    }
                    data["newest_list"] = dataPageList[sliceOffset..<dataPageList.count].reversed() as Array
                }
                return SiteResponse(status: .OK(view: "viewcomic.mustache", data: data), session: session)
            }
            return SiteResponse(status: .NotFound, session: session)
        } catch WebFrameworkError.BBCodeError(let msg) {
            return SiteResponse(status: .Error(message: msg), session: session)
        } catch {
            return SiteResponse(status: .Error(message: "DB failed"), session: session)
        }
    }

    public func addComic(session: SessionInfo) -> SiteResponse {
        let data: [String: Any] = ["lang": ComicI18n.instance.getI18n(session.locale)]
        return SiteResponse(status: .OK(view: "addcomic.mustache", data: data), session: session)
    }

    public func postAddComic(session: SessionInfo, title: String, author: String, description: String) -> SiteResponse {
        var data: [String: Any] = ["lang": ComicI18n.instance.getI18n(session.locale)]
        data["title"] = title
        data["author"] = author
        data["description"] = description
        do {
            _ = try self.utilities.BBCode2HTML(bbcode: description, local: session.locale)
            let comicId = try self.dataManager.addComic(title: title, author: author, poster: "guest", description: description)
            return SiteResponse(status: .Redirect(location: "/comic/\(comicId)"), session: session)
        } catch WebFrameworkError.RuntimeError(let msg) {
            data["error"] = msg
            return SiteResponse(status: .OK(view: "addcomic.mustache", data: data), session: session)
        } catch WebFrameworkError.BBCodeError(let msg) {
            data["error"] = msg
            return SiteResponse(status: .OK(view: "addcomic.mustache", data: data), session: session)
        } catch {
            return SiteResponse(status: .Error(message: "DB failed"), session: session)
        }
    }

    public func editComic(session: SessionInfo, comicId: UInt32) -> SiteResponse {
        do {
            if let comic = try self.dataManager.getComic(id: comicId) {
                var data: [String: Any] = ["lang": ComicI18n.instance.getI18n(session.locale)]
                data["comic_id"] = comic.id
                data["title"] = i18n(comic.title, locale: session.locale)
                data["author"] = comic.author
                data["poster"] = comic.poster
                data["description"] = comic.description.stringByEncodingHTML_NoConvertCRLF

                return SiteResponse(status: .OK(view: "editcomic.mustache", data: data), session: session)
            }
            return SiteResponse(status: .NotFound, session: session)
        } catch {
            return SiteResponse(status: .Error(message: "DB failed"), session: session)
        }
    }

    public func postUpdateComic(session: SessionInfo, comicId: UInt32, title: String, author: String, description: String) -> SiteResponse {
        var data: [String: Any] = ["lang": ComicI18n.instance.getI18n(session.locale)]
        data["title"] = title
        data["author"] = author
        data["description"] = description
        do {
            guard let comic = try self.dataManager.getComic(id: comicId) else {
                return SiteResponse(status: .NotFound, session: session)
            }
            _ = try self.utilities.BBCode2HTML(bbcode: description, local: session.locale)
            guard self.dataManager.updateComic(id: comicId, title: title, author: author, pageCount: comic.pageCount, description: description) else {
                return SiteResponse(status: .Error(message: "DB failed"), session: session)
            }
            return SiteResponse(status: .Redirect(location: "/comic/\(comicId)"), session: session)
        } catch WebFrameworkError.RuntimeError(let msg) {
            data["error"] = msg
            return SiteResponse(status: .OK(view: "editcomic.mustache", data: data), session: session)
        } catch WebFrameworkError.BBCodeError(let msg) {
            data["error"] = msg
            return SiteResponse(status: .OK(view: "editcomic.mustache", data: data), session: session)
        } catch {
            return SiteResponse(status: .Error(message: "DB failed"), session: session)
        }
    }

    public func toolAddFile(pageId: UInt32, filename: String, localname: String, mimetype: String, size: UInt32) throws {
        try self.dataManager.addFile(pageId: pageId, filename: filename, localname: localname, mimetype: mimetype, size: size)
    }

    public func error(session: SessionInfo, message: String) -> SiteResponse {
        return SiteResponse(status: .OK(view: "error.mustache", data: ["message": message]), session: session)
    }
}

extension Dictionary {
    mutating func update(other:Dictionary) {
        for (key,value) in other {
            self.updateValue(value, forKey:key)
        }
    }
}

extension String {
    /// Returns the String with all special HTML characters encoded.
    public var stringByEncodingHTML_NoConvertCRLF: String {
        var ret = ""
        var g = self.unicodeScalars.makeIterator()
        while let c = g.next() {
            if c < UnicodeScalar(0x0009) {
                if let scale = UnicodeScalar(0x0030 + UInt32(c)) {
                    ret.append("&#x")
                    ret.append(String(Character(scale)))
                    ret.append(";")
                }
            } else if c == UnicodeScalar(0x0022) {
                ret.append("&quot;")
            } else if c == UnicodeScalar(0x0026) {
                ret.append("&amp;")
            } else if c == UnicodeScalar(0x0027) {
                ret.append("&#39;")
            } else if c == UnicodeScalar(0x003C) {
                ret.append("&lt;")
            } else if c == UnicodeScalar(0x003E) {
                ret.append("&gt;")
            } else if c > UnicodeScalar(126) {
                ret.append("&#\(UInt32(c));")
            } else {
                ret.append(String(Character(c)))
            }
        }
        return ret
    }
}
