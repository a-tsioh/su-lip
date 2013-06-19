database IME {
  // loaded = 1 iff the data has been loaded into mongdb already
	// you have to manually delete the db to be able to re-call the loading function
	int /loaded

	// the data is stored as a tree indexed with a record of a prefix and the last syllabe of a form
	node /prefix_tree[{pfx,syl}]
}



// a syllabe is analyzed as an initial (consonnant), a medial voyel cluster, a final consonnant and a tone
type syllabe = {string init, string med, string final, string tone}


// a node of the prefix tree contains its key elements, 
// a list of the syllables that lead to its children,
// a list of candidates in 漢字 and a spelling in Taiwan Romanization System (trs)
type node = {
	string pfx,
	syllabe syl,
	list(syllabe) children,
	list(string) candidates,
	string trs
}



// module to manipulate the Tree
module PrefixTree{

	// build a new prefix by adding a syllable at the end from a prefix
	function append_to_pfx(pfx,syl){
		"{pfx}-{Model.string_of_syllabe(syl)}"
	}

	// add some data to the DB at some point in the Tree
	function add_with_prefix(pfx,syls,hj,trs){
		match(syls){
			case []:{failure}
			case [syl]: // end of word
				indb = ?/IME/prefix_tree[{~pfx, ~syl}]
				match(indb){
					case {none}: /IME/prefix_tree[{~pfx, ~syl}] <- {~pfx, ~syl, children: [], candidates:[hj], ~trs}
					case {some: entry}:
						if(List.contains(hj,entry.candidates) == {false})
							/IME/prefix_tree[{~pfx,~syl}]/candidates <+ hj
						/IME/prefix_tree[{~pfx,~syl}]/trs <- trs
				}
				{success}
			case [syl|tl]: //prefixing
				indb = ?/IME/prefix_tree[{~pfx, ~syl}]
				match(indb){
					case {none}: 
						/IME/prefix_tree[~{pfx,syl}] <- {~pfx, ~syl, children: [List.head(tl)], candidates:[], trs:""}
						add_with_prefix(append_to_pfx(pfx,syl),tl,hj,trs)
					case {some: entry}:
						next = List.head(tl)
						if(List.contains(next, entry.children) == {false})
							/IME/prefix_tree[~{pfx,syl}]/children <+ List.head(tl)
						add_with_prefix(append_to_pfx(pfx,syl), tl, hj, trs)
				}
		}
	}

	// add data to the DB from the root of the Tree
	function add(syls,hj,trs){
		add_with_prefix("",syls,hj,trs)
	}
	
	
	// return a couple (prefix,syllable) from a list of syllables
	function syls_to_pfx_syl(syls){
		recursive function recf(pfx,syls){
			match(syls) {
				case [] :{none}
				case [syl]: {some: (pfx,syl)}
				case [syl|tl]: recf(append_to_pfx(pfx,syl),tl)
			}
		}
		recf("",syls)
	}


	// query the DB for all the possible continuations from a node in the Tree
	function lookup_prefix(pfx,syl,acc){
		indb = ?/IME/prefix_tree[~{pfx,syl}].{candidates,children,trs}
		match(indb){
			case {none}: acc //nothing to add
			case ~{some}: 
				acc = List.add(annotate_candidate_list(some),acc)
				pfx = append_to_pfx(pfx,syl)
				List.fold_left(function(a,chld){lookup_prefix(pfx,chld,a)},acc,some.children)
		}
	}


	// convert a DbSet to an option list of data
	function fuzzy_opt(dbs){
		l = Iter.to_list(DbSet.iterator(dbs))
		match(l){
			case []: {none}
			case _: {some:l}
		}

	}

	// query the DB, the fuzzy way
	function generate_next_data(syl,p) {
		match((syl.final,syl.tone)){
			case ("",""): fuzzy_opt(/IME/prefix_tree[pfx==p and syl.init==syl.init and syl.med==syl.med].{candidates,syl,pfx,children,trs})
			case ("",_): fuzzy_opt(/IME/prefix_tree[pfx==p and syl.init==syl.init and syl.med==syl.med and syl.tone==syl.tone].{candidates,syl,pfx,children,trs})
			case (_,""): fuzzy_opt(/IME/prefix_tree[pfx==p and syl.init==syl.init and syl.med==syl.med and syl.final==syl.final].{candidates,syl,pfx,children,trs})
			case _:  fuzzy_opt(/IME/prefix_tree[pfx==p and syl==syl].{candidates,syl,pfx,children,trs})
		}
	}

	// add TRS to each candidate of a list (build a list of records)
	function annotate_candidate_list(solution){
		trs = solution.trs
		candidates = solution.candidates
		List.map(function(x){{hj:x,~trs}},candidates)
	}


	// Fuzzy Query function that allow for underspecified syllables
	function fuzzy_lookup_prefix(syls){
		recursive function aux(pfx_list,syls){
			match(syls){
				case []: {fuzzy:[], fuzzy_prefix:[]} //empty result for an empty query
				case [syl]: //last syllable of the query
					next_data = List.flatten(List.filter_map( generate_next_data(syl,_),pfx_list))
					//cand_list = List.fold_left(function(a,l){List.add(l,a)},cand_list, List.map(function(x){annotate_candidate_list(x.candidates,x.trs)},next_data))
					cand_list = List.map(annotate_candidate_list,next_data)
					follow_up = List.map(function(x){(append_to_pfx(x.pfx,x.syl),x.children)},next_data)
					follow_up = List.flatten(List.map(function(x){List.map(function(chld){{pfx:x.f1,syl:chld}},x.f2)},follow_up))
					//List.add(cand_list, List.map(function(child){lookup_prefix(child.pfx,[child.syl],[])},follow_up))
					completion = List.map(function(child){lookup_prefix(child.pfx,child.syl,[])},follow_up)
					{fuzzy:List.flatten(cand_list), fuzzy_prefix:List.flatten(List.flatten(completion))}
				case [syl|tl] : // basic case
					next_data = List.flatten(List.filter_map(generate_next_data(syl,_),pfx_list))
					pfx_list = List.map(function(x){append_to_pfx(x.pfx,x.syl)},next_data)
					aux(pfx_list,tl)
			}
		}
		aux([""],syls)
	}


		

/*
	function fuzzy_lookup(syls){
		match(syls_to_pfx_syl(syls)){
			case {none}: {none}
			case {some: (pfx,syl)}:
				match((syl.final, syl.tone)){
					case ("",""): fuzzy_opt(/IME/prefix_tree[pfx==pfx and syl.init==syl.init and syl.med==syl.med]/candidates)
					case ("",_): fuzzy_opt(/IME/prefix_tree[pfx==pfx and syl.init==syl.init and syl.med==syl.med and syl.tone==syl.tone]/candidates)
					case (_,""): fuzzy_opt(/IME/prefix_tree[pfx==pfx and syl.init==syl.init and syl.med==syl.med and syl.final==syl.final]/candidates)
					case (_,_):  ?/IME/prefix_tree[~{pfx,syl}]/candidates
				}
		}
	}*/

				
	
}


module Model {
	function trs_to_syl_list_opt(trs) {
	  parsed = Parser.try_parse(poj_word, trs)
		match(parsed){
			case {none}: {none}
			case {some: w}:
				if(is_valid_word(w)) {
					{some: List.filter_map(function {
						case {~syl}: {some: syl}
						case _: {none}},w)}
				}
				else {
				 {none}
				}
		}
	}
		

	function lookup(trs){
		sl = trs_to_syl_list_opt(trs)
		res = match(sl) {
			case {none}: {fuzzy:[], fuzzy_prefix:[]}
			case ~{some}: PrefixTree.fuzzy_lookup_prefix(some)
			//{some: List.flatten(PrefixTree.lookup_prefix("",some,[]))}
		}
		res
	}

	function query(js){
		match(js){
			case {~query }: result = lookup(query)
				OpaSerialize.Json.serialize(result) |> Json.to_string
			default:	OpaSerialize.Json.serialize({fuzzy:[],fuzzy_prefix:[]}) |> Json.to_string
		}	
	
	}

	function is_valid_word(w){
		pb = List.find(function {
			case {other: _}: {true}
			case _: {false}
		},w)
		match(pb) {
			case {some: _}: {false}
			case {none}: {true}
		}
	}
			

  function add_couple(trs,hj) {
		sl = trs_to_syl_list_opt(trs)
		match(sl) {
			case {none}:{failure}
			case {some: syls}:
					add(syls,hj,trs)
			
		}
	}
	

	function add(_,hj,trs){
		sl = trs_to_syl_list_opt(trs)
		match(sl){
			case {none}:println("problem with {trs}"); {none}
			case {~some}: PrefixTree.add(some,hj,trs)
		}
	}

	function load_data_to_db() {
		if(/IME/loaded == 0) { 
		List.iter(function(l){(hz,trs) = split_line(l);  add_couple(trs,hz) |> ignore },load_file(Config.datafile))
		/IME/loaded <- 1
		println("done")
		{success}}
		else {
			{failure}
		}
  }

 	function load_file(path){
	  println("loading... {path}...")
		bin = File.read(path)
		String.explode("\n", string_of_binary(bin))
		}


	function split_line(x) {
		l = String.explode("\t",x)
		hz = List.head(l)
		trs = match(List.tail(l)){
			case [x|_]: x
			case []: "error"
		}
		(hz,String.lowercase(trs))
	}
  
  
  function key_of_word(trs){
    List.filter_map(function(x) {
      match(x) {
        case ~{syl}: {some: syl}
	case _ : {none}
	}
      }, trs)
  }


  // model code goes here
  poj_i = parser {
  	case l= ("w"|"tsh"|"ts"|"th"|"t"|"s"|"h"|"b"|"chh"|"ch"|"g"|"j"|"kh"|"k"|"l"|"m"|"ng"|"n"|"ph"|"p"): l
  }
  poj_m = parser {
  	case l= ([aeiou]+|"ng"|"m") : l
  }
  poj_f = parser {
  	case l= ("ng"|"nn"|"N"|"m"|"n"|"p"|"t"|"h"|"k"): l
  }
  poj_t = parser {
  	case l=[1-8]: String.of_char(l)
  }
  poj_syl = parser {
  	case i=poj_i m=poj_m f=poj_f t=poj_t: {init: Text.to_string(i), med: Text.to_string(m), final: Text.to_string(f), tone: t}
  	case i=poj_i m=poj_m f=poj_f: {init: Text.to_string(i), med: Text.to_string(m), final: Text.to_string(f), tone: ""}
  	case m=poj_m f=poj_f t=poj_t: {init: "", med: Text.to_string(m), final: Text.to_string(f), tone: t}
  	case m=poj_m f=poj_f: {init: "", med: Text.to_string(m), final: Text.to_string(f), tone: ""}

  	case i=poj_i m=poj_m t=poj_t: {init: Text.to_string(i), med: Text.to_string(m), final: "", tone: t}
  	case i=poj_i m=poj_m: {init: Text.to_string(i), med: Text.to_string(m),final: "", tone: ""}
  	case m=poj_m t=poj_t: {init: "", med: Text.to_string(m), final: "", tone: t}
  	case m=poj_m: {init: "", med: Text.to_string(m), final: "", tone: ""}
  }


  function string_of_syllabe(syl){
  	"{syl.init}.{syl.med}.{syl.final}.{syl.tone}"
  }


  poj_word_element = parser {
	case "--": {dt}
	case "-" : {st}
	case s=([\u0061-\u002c\u002e-\u4000]+): match(Parser.try_parse(poj_syl,normalize("{s}"))) {
	  case {some: syl}: ~{syl}
	  case {none}: {other:s}
	  }
	}
  
	poj_word = parser {
  	case res=poj_word_element*: res
  }

  function string_of_word(w){
    List.map(function(x){ match(x){
      case {dt}: "--"
      case {st}: "-"
      case ~{syl}: string_of_syllabe(syl)
      case ~{other}: "??{other}??"
    }},w) |> String.flatten
  }

  process_tones = parser {
	case x=tone_to_number : x
	case c=(.) : "{c}"
  }

  function normalize(s) {
    p1 = parser {
    	case out=process_tones*: out
	  }
    p2 = parser {
        case left=([a-zA-Z]*) t=([0-9]) right=([a-zA-Z]*): String.of_list(function(x){"{x}"},"",[left,right,t])
    }
    res = Parser.try_parse(p1,s)
    match(res){
      case {none}: s
      case {some: l}: match(Parser.try_parse(p2,String.of_list(function(x) {x}, "", l))){
          case {none}: s
	  case {some: x}:x
	  }
      }
  }

  tone_to_number =  parser {
    case "A\u0300": "A3"
    case "A\u0301": "A2"
    case   "A\u0302": "A5"
    case   "A\u0304": "A7"
    case   "A\u030d": "A8"
    case   "E\u0300": "E3"
    case   "E\u0301": "E2"
    case   "E\u0302": "E5"
    case   "E\u0304": "E7"
    case   "E\u030d": "E8"
    case   "I\u0300": "I3"
    case   "I\u0301": "I2"
    case   "I\u0302": "I5"
    case   "I\u0304": "I7"
    case   "I\u030d": "I8"
    case   "M\u0300": "M3"
    case   "M\u0301": "M2"
    case   "M\u0302": "M5"
    case   "M\u0304": "M7"
    case   "M\u030d": "M8"
    case   "N\u0300": "N3"
    case   "N\u0301": "N2"
    case   "N\u0302": "N5"
    case   "N\u0304": "N7"
    case   "N\u030d": "N8"
    case   "O\u0300": "O3"
    case   "O\u0300\u0358": "Ou3"
    case   "O\u0301": "O2"
    case   "O\u0301\u0358": "Ou2"
    case   "O\u0302": "O5"
    case   "O\u0302\u0358": "Ou5"
    case   "O\u0304": "O7"
    case   "O\u0304\u0358": "Ou7"
    case   "O\u030d": "O8"
    case   "O\u030d\u0358": "Ou8"
    case   "O\u0358": "Ou"
    case   "U\u0300": "U3"
    case   "U\u0301": "U2"
    case   "U\u0302": "U5"
    case   "U\u0304": "U7"
    case   "U\u030d": "U8"
    case   "a\u0300": "a3"
    case   "a\u0301": "a2"
    case   "a\u0302": "a5"
    case   "a\u0304": "a7"
    case   "a\u030d": "a8"
    case   "e\u0300": "e3"
    case   "e\u0301": "e2"
    case   "e\u0302": "e5"
    case   "e\u0304": "e7"
    case   "e\u030d": "e8"
    case   "i\u0300": "i3"
    case   "i\u0301": "i2"
    case   "i\u0302": "i5"
    case   "i\u0304": "i7"
    case   "i\u030d": "i8"
    case   "m\u0300": "m3"
    case   "m\u0301": "m2"
    case   "m\u0302": "m5"
    case   "m\u0304": "m7"
    case   "m\u030d": "m8"
    case   "n\u0300": "n3"
    case   "n\u0301": "n2"
    case   "n\u0302": "n5"
    case   "n\u0304": "n7"
    case   "n\u030d": "n8"
    case   "o\u0300": "o3"
    case   "o\u0300\u0358": "ou3"
    case   "o\u0301": "o2"
    case   "o\u0301\u0358": "ou2"
    case   "o\u0302": "o5"
    case   "o\u0302\u0358": "ou5"
    case   "o\u0304": "o7"
    case   "o\u0304\u0358": "ou7"
    case   "o\u030d": "o8"
    case   "o\u030d\u0358": "ou8"
    case   "o\u0358": "ou"
    case   "u\u0300": "u3"
    case   "u\u0301": "u2"
    case   "u\u0302": "u5"
    case   "u\u0304": "u7"
    case   "u\u030d": "u8"
    case   "\u00c0": "A3"
    case   "\u00c1": "A2"
    case   "\u00c2": "A5"
    case   "\u00c8": "E3"
    case   "\u00c9": "E2"
    case   "\u00ca": "E5"
    case   "\u00cc": "I3"
    case   "\u00cd": "I2"
    case   "\u00ce": "I5"
    case   "\u00d2": "O3"
    case   "\u00d2\u0358": "Ou3"
    case   "\u00d3": "O2"
    case   "\u00d3\u0358": "Ou2"
    case   "\u00d4": "O5"
    case   "\u00d4\u0358": "Ou5"
    case   "\u00d9": "U3"
    case   "\u00da": "U2"
    case   "\u00db": "U5"
    case   "\u00e0": "a3"
    case   "\u00e1": "a2"
    case   "\u00e2": "a5"
    case   "\u00e8": "e3"
    case   "\u00e9": "e2"
    case   "\u00ea": "e5"
    case   "\u00ec": "i3"
    case   "\u00ed": "i2"
    case   "\u00ee": "i5"
    case   "\u00f2": "o3"
    case   "\u00f2\u0358": "ou3"
    case   "\u00f3": "o2"
    case   "\u00f3\u0358": "ou2"
    case   "\u00f4": "o5"
    case   "\u00f4\u0358": "ou5"
    case   "\u00f9": "u3"
    case   "\u00fa": "u2"
    case   "\u00fb": "u5"
    case   "\u0100": "A7"
    case   "\u0101": "a7"
    case   "\u0112": "E7"
    case   "\u0113": "e7"
    case   "\u012a": "I7"
    case   "\u012b": "i7"
    case   "\u0143": "N2"
    case   "\u0144": "n2"
    case   "\u014c": "O7"
    case   "\u014c\u0358": "Ou7"
    case   "\u014d": "o7"
    case   "\u014d\u0358": "ou7"
    case   "\u016a": "U7"
    case   "\u016b": "u7"
    case   "\u01f8": "N3"
    case   "\u01f9": "n3"
    case   "\u1e3e": "M2"
    case   "\u1e3f": "m2"
    case   "\u207f": "nn"}
}
