package piabrota.thesis

import SectionKey as Key

/** The problems of a thesis.json, one line each (validate.jq of the shell version). The sections
  * are always checked; `final` also wants the front-page data filled (no "A PREENCHER"). None when
  * thesis.json cannot be checked at all (jq stopped with an error there). This is the edge where
  * thesis.json is checked, so it reads the JSON values as they are.
  */
object Validate:
  def problems(t: ujson.Value, profile: Profile, `final`: Boolean): Option[List[String]] =
    val courses = profile.courses.map(_.name)
    val targets = profile.cite.scoreTargets.keys.toList
    def field(key: String): Option[ujson.Value] = J.get(t, key)
    def unfilledStr(v: Option[ujson.Value]): Boolean = v.flatMap(_.strOpt).isEmpty || isTodo(v)
    def num(v: Option[ujson.Value]): Option[Double] = v.flatMap(_.numOpt)

    val unfilled = List(
      Option.when(unfilledStr(field(ThesisKey.Title)))("title is not filled"),
      Option.when(unfilledStr(field(ThesisKey.Author)))("author is not filled"),
      Option.when(unfilledStr(field(ThesisKey.Advisor)))("advisor is not filled"),
      Option.when(unfilledStr(field(ThesisKey.TitleEn)))("title_en is not filled"),
      Option.when(unfilledStr(field(ThesisKey.AuthorRef)))("author_ref is not filled (SURNAME, Given names)"),
    ).flatten

    val month = num(field(ThesisKey.Month))
    val year = num(field(ThesisKey.Year))
    val examiners = field(ThesisKey.Examiners).flatMap(_.arrOpt)
    val sectionsValue = field(ThesisKey.Sections)
    val meta = List(
      Option.when(!field(ThesisKey.Course).flatMap(_.strOpt).exists(courses.contains))(
        s"""course must be one of the Poli courses (norma 2026, 5.1), as "Engenharia X": ${courses.mkString("; ")}"""),
      Option.when(month.forall(m => m < 1 || m > 12 || m.floor != m))("month must be 1 to 12"),
      Option.when(year.forall(y => y < 2000 || y > 2100))("year must be a four-digit number"),
      Option.when(!field(ThesisKey.Language).contains(ujson.Str(ThesisValue.Language)))("language must be pt-BR (Res. 05/2012; norma 2026, 6.1)"),
      Option.when(!field(ThesisKey.CitationStyle).contains(ujson.Str(ThesisValue.CitationStyle)))("citation_style must be author-date: one system for the whole work"),
      Option.when(examiners.forall(_.exists(_.strOpt.isEmpty)))("examiners must be a list of strings"),
      Option.when(sectionsValue.flatMap(_.arrOpt).forall(_.isEmpty))("sections must be a non-empty list"),
    ).flatten

    val sections: Option[List[ujson.Value]] = sectionsValue match
      case None | Some(ujson.Null) | Some(ujson.False) => Some(Nil)
      case Some(ujson.Arr(a))                          => Some(a.toList)
      case _                                           => None
    sections.flatMap { s =>
      // `has` of jq stops on a key that is not a string; so does this check.
      val classes = s.map(x => J.get(x, Key.CiteClass).filterNot(J.falsy).getOrElse(ujson.Str(Key.DefaultCiteClass)))
      Option.when(classes.forall(_.strOpt.isDefined)) {
        meta ++ sectionProblems(s, targets) ++ (if `final` then unfilled else Nil)
      }
    }

  /** null, missing, empty or "A PREENCHER". */
  private def isTodo(v: Option[ujson.Value]): Boolean = v match
    case None | Some(ujson.Null) | Some(ujson.Str("")) => true
    case Some(ujson.Str(s))                             => s == ThesisValue.ToFill
    case _                                              => false

  /** jq's string interpolation: a string as it is, anything else as compact JSON. */
  private def show(v: Option[ujson.Value]): String = v match
    case Some(ujson.Str(s)) => s
    case Some(ujson.Num(d)) => Text.jqNum(d)
    case Some(other)        => other.render()
    case None               => "null"

  private def sectionProblems(s: List[ujson.Value], targets: List[String]): List[String] =
    def g(x: ujson.Value, key: String) = J.get(x, key)
    def id(x: ujson.Value) = show(g(x, Key.Id))
    def str(x: ujson.Value, key: String) = g(x, key).flatMap(_.strOpt)
    def is(x: ujson.Value, key: String, value: String) = str(x, key).contains(value)
    def role(x: ujson.Value, r: Role) = is(x, Key.Role, r.render)
    def kind(x: ujson.Value, k: Kind) = is(x, Key.Kind, k.render)
    def groups(key: String) =
      s.groupBy(x => g(x, key).getOrElse(ujson.Null)).toList
        .sortWith((a, b) => J.compare(Some(a._1), Some(b._1)) < 0).map(_._2).filter(_.length > 1)
    val kinds = Kind.values.toList.map(_.render)
    val roles = Role.values.toList.map(_.render)
    val planned = List(SectionState.Todo, SectionState.Omit).map(_.render)
    List(
      groups(Key.Id).map(x => s"the section id ${id(x.head)} is in the list twice"),
      groups(Key.Order).map(x => s"the order ${show(g(x.head, Key.Order))} is used by ${x.map(y => str(y, Key.Id).getOrElse(g(y, Key.Id).filterNot(_.isNull).map(J.rawValue).getOrElse(""))).mkString(", ")}"),
      s.filter(x => !str(x, Key.Id).exists(_.matches("^[A-Za-z0-9_-]+$"))).map(x => s"the section id ${id(x)} is not letters, digits, - and _"),
      s.filter(x => !str(x, Key.Kind).exists(kinds.contains)).map(x => s"${id(x)}: kind must be ${kinds.init.mkString(", ")} or ${kinds.last}"),
      s.filter(x => !str(x, Key.Role).exists(roles.contains)).map(x => s"${id(x)}: role must be ${roles.init.mkString(", ")} or ${roles.last}"),
      s.filter(x => role(x, Role.Chapter) && !kind(x, Kind.Textual)).map(x => s"${id(x)}: a chapter is textual"),
      s.filter(x => role(x, Role.Appendix) && !kind(x, Kind.Postextual)).map(x => s"${id(x)}: an appendix is postextual"),
      s.filter(x => !role(x, Role.Chapter) && !role(x, Role.Appendix) && !kind(x, Kind.Pretextual))
        .map(x => s"${id(x)}: ${show(g(x, Key.Role))} is pretextual"),
      s.filter(x => str(x, Key.Title).isEmpty || isTodo(g(x, Key.Title))).map(x => s"${id(x)}: title is not filled"),
      s.filter(x => str(x, Key.Brief).isEmpty || isTodo(g(x, Key.Brief))).map(x => s"${id(x)}: brief is not filled"),
      s.filter(x => str(x, Key.Brief).exists(b => "sections/|@cap:".r.findFirstIn(b).isDefined))
        .map(x => s"${id(x)}: a brief may not point at the text of another section (sections are independent)"),
      s.filter(x => g(x, Key.Order).flatMap(_.numOpt).isEmpty).map(x => s"${id(x)}: order must be a number"),
      s.filter(x => g(x, Key.TargetWords).flatMap(_.numOpt).forall(_ < 0)).map(x => s"${id(x)}: target_words must be a number"),
      s.filter(x => !str(x, Key.Status).exists(planned.contains)).map(x => s"${id(x)}: status in thesis.json is todo or omit (progress is in state/)"),
      s.filter(x => !targets.contains(g(x, Key.CiteClass).filterNot(J.falsy).map(J.rawValue).getOrElse(Key.DefaultCiteClass)))
        .map(x => s"${id(x)}: cite_class must be one of ${targets.sorted.mkString(", ")}"),
      s.filter { x =>
        g(x, Key.Sources).filterNot(J.falsy) match
          case None               => false
          case Some(ujson.Arr(a)) => !a.forall(_.strOpt.exists(_.matches("^[A-Za-z0-9_:.-]+$")))
          case _                  => true
      }.map(x => s"${id(x)}: sources must be a list of keys"),
      s.filter { x =>
        (role(x, Role.Resumo) || role(x, Role.Abstract)) &&
          g(x, Key.Keywords).filterNot(J.falsy).exists(_.arrOpt.isEmpty)
      }.map(x => s"${id(x)}: keywords must be a list"),
    ).flatten
