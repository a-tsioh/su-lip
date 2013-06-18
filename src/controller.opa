module Controller {

  // URL dispatcher of your application; add URL handling as needed

	function webservice(){
		match (HttpRequest.get_method()) {
    	case {some: method} :
        match (method) {
        case {post}:
            jsquery =Json.of_string(HttpRequest.get_body() ? "") 
						match(jsquery){
								case {~some}: 
									query = OpaSerialize.Json.unserialize(some) ? {query:""} 
									Resource.raw_response("{Model.query(query)}\n","text/plain", {success})
								case {none}: Resource.raw_status({bad_request})
						}
        default:
            Resource.raw_status({method_not_allowed});
        }
    	default:
        Resource.raw_status({bad_request});
    }
	
	}


	function url_do(url){
		match(url){
			case {path: [] ...}:	webservice()
			case {path: ["_ws_"|_] ...}: webservice()
			case {path: ["build_db"|_] ...}: match(Model.load_data_to_db()){
				case {success}:	Resource.raw_response("ok","text/plain",{success})
				case {failure}: Resource.raw_response("database already loaded","text/plain",{success})
				}
			case {~path ...}: Resource.raw_status({bad_request})
		}
	}

}

resources = @static_resource_directory("resources")

Server.start(Server.http, [
  { register:
    [ { doctype: { html5 } },
      { js: [ ] },
      { css: [ "/resources/css/style.css"] }
    ]
  },
  { ~resources },
	{ dispatch: Controller.url_do}
])
