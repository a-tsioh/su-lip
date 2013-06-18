module View {

   // View code goes here

  function page_template(title, content) {
    html =
      <div class="navbar navbar-fixed-top">
        <div class=navbar-inner>
          <div class=container>
            <a class=brand href="./index.html">IME</>
          </div>
        </div>
      </div>
      <div id=#main class=container-fluid>
	{"\u00d4"}
        {content}
        <div id=#result />
      </div>
    Resource.page(title, html)
  }

  function default_page() {
    content =
      <div class="hero-unit">
        <textarea id=#textarea rows="10" cols="80" onnewline={function(_) {onchange()}} />
      </div>
    page_template("Default page", content)
  }


  function onchange(){
    str = String.strip(Dom.get_value(#textarea))
    result = Model.lookup(str)
    output = <>
		{OpaSerialize.Json.serialize(result) |> Json.to_string}
	</>
    #result = output
  // load_data()
	    
  }
  function load_data(){
  	result = Model.load_data_to_db()
    match(result){
    	case {success}: #result =+ <>OK!</>
			case {failure}: #result =+ <>NOK:( </>
  	}
	}

}
