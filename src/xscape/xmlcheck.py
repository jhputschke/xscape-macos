"""
The checks xscape-run and runJetscape make before X-SCAPE starts.

* modules(): the modules a user XML makes X-SCAPE create, as JetScape::DetermineTaskListFromXML
  reads it, and what this wheel lacks of them (missing_modules()). The wheel is built without
  ROOT, HepMC, SMASH, FreestreamMilne, CLVisc, IPGlasma and the FNO hydro, and X-SCAPE only
  warns when a module isn't there, then runs without it.
* check_run() also refuses Pythia LHAPDF6 sets (PDF:pSet = LHAPDF6:...): the wheel's Pythia
  has no LHAPDF6 plugin and crashes in its setup.
* automatic_setup(): False when the XML turns automatic module setup off. Such XMLs are
  written for C++ test programs that build their own pipeline; runJetscape runs no module
  with them and exits 0.
* cwd_problems(): what a run in the current directory would miss (runJetscape without
  xscape-run): 3dMCGlauber's tables/, MUSIC's music_input, '../' paths.

The '../' paths and the user XML's tags are checked by X-SCAPE's run_xml.py, which
run_in_workdir.sh calls.
"""

from __future__ import annotations

import os
import xml.etree.ElementTree as ET

#: <Stage><Child> -> the module X-SCAPE creates (JetScape::DetermineTaskListFromXML)
STAGE_MODULES = {
    "IS": {"Trento": "TrentoInitial", "initial_profile_path": "InitialFromFile",
           "IPGlasma": "IPGlasma", "MCGlauber": "MCGlauber",
           "initial_Ncoll_list": "NcollListFromFile"},
    "Hard": {"PGun": "PGun", "PythiaGun": "PythiaGun", "epemGun": "epemGun",
             "EPGun": "EPGun"},
    "Preequilibrium": {"NullPreDynamics": "NullPreDynamics", "Glasma": "Glasma",
                       "FreestreamMilne": "FreestreamMilne"},
    "Hydro": {"Brick": "Brick", "Gubser": "Gubser", "hydro_from_file": "HydroFromFile",
              "MUSIC": "MUSIC", "CLVisc": "CLVisc"},
    "Eloss": {"Matter": "Matter", "Lbt": "Lbt", "Martini": "Martini", "AdSCFT": "AdSCFT"},
    "SoftParticlization": {"iSS": "iSS"},
    "Afterburner": {"SMASH": "SMASH"},
}
#: top-level elements that are modules themselves
TOP_MODULES = ("PartonPrinter", "HadronPrinter", "RootBulkWriter", "FastRootBulkWriter")
#: <JetHadronization><name> -> the module
HADRONIZATION = {"colored": "ColoredHadronization", "colorless": "ColorlessHadronization",
                 "iColored": "iColoredHadronization", "hybrid": "HybridHadronization"}
#: the writers X-SCAPE switches on by <Name> on (JetScape::CheckForWriterFromXML)
WRITERS = ("JetScapeWriterAscii", "JetScapeWriterAsciiGZ", "JetScapeWriterHepMC",
           "JetScapeWriterRootHepMC", "JetScapeWriterFinalStatePartonsAscii",
           "JetScapeWriterFinalStateHadronsAscii", "JetScapeWriterQnVectorAscii")
#: what a module missing from the wheel needs, for the message
WHY = {"RootBulkWriter": "ROOT", "FastRootBulkWriter": "ROOT",
       "JetScapeWriterRootHepMC": "ROOT and HepMC", "JetScapeWriterHepMC": "HepMC"}


def _text(root, *path):
    el = root.find("/".join(path))
    return (el.text or "").strip() if el is not None else None


def modules(user_xml: str, main_xml: str | None = None) -> list[tuple[str, str]]:
    """(module name, the XML element that asks for it) for each module the user XML makes
    X-SCAPE create with automatic module setup."""
    user = ET.parse(user_xml).getroot()
    main = ET.parse(main_xml).getroot() if main_xml else None
    out = []
    for stage, table in STAGE_MODULES.items():
        block = user.find(stage)
        if block is None:
            continue
        for child in block:
            name = table.get(child.tag)
            if child.tag.find("CustomModule") >= 0:
                name = child.tag
            if name is None:
                continue
            if stage == "Hard" and child.tag == "PythiaGun" and block.find("ISR") is not None:
                out += [("PythiaIsrGun", "<Hard><PythiaGun> with <Hard><ISR>"),
                        ("MCGlauberGenString", "<Hard><ISR>")]
                continue
            out.append((name, f"<{stage}><{child.tag}>"))
    if user.find("JetHadronization") is not None:
        hname = _text(user, "JetHadronization", "name")
        if hname is None and main is not None:
            hname = _text(main, "JetHadronization", "name")
        if hname:
            out.append((HADRONIZATION.get(hname, hname),
                        f"<JetHadronization><name>{hname}"))
    for tag in TOP_MODULES:
        if user.find(tag) is not None:
            out.append((tag, f"<{tag}>"))
    for tag in WRITERS:
        value = _text(user, tag)
        if value is None and main is not None:
            value = _text(main, tag)
        if value and "on" in value:
            out.append((tag, f"<{tag}> {value}"))
    return out


def automatic_setup(user_xml: str, main_xml: str | None = None) -> bool:
    """Whether X-SCAPE builds the task list from the XML (the main XML's default: true)."""
    for xml in (user_xml, main_xml):
        if xml:
            value = _text(ET.parse(xml).getroot(), "enableAutomaticTaskListDetermination")
            if value is not None:
                return "false" not in value
    return True


def registered() -> set[str]:
    """The modules this wheel's X-SCAPE can create."""
    from jetscape import pyjetscape_core
    return set(pyjetscape_core.registered_modules())


def missing_modules(user_xml: str, main_xml: str | None = None,
                    have: set[str] | None = None) -> list[str]:
    """"<module> (<element>; needs ...)" for each module the XML asks for that the wheel
    lacks."""
    have = registered() if have is None else have
    out = []
    for name, where in modules(user_xml, main_xml):
        if name not in have:
            why = WHY.get(name)
            if name.startswith("CustomModule"):
                why = "a module of one's own: register it from Python (jetscape.module)"
            out.append(f"{name} ({where}{'; needs ' + why if why else ''})")
    return out


def check_run(user_xml: str, main_xml: str | None) -> list[str]:
    """Why xscape-run refuses ``user_xml`` (empty: it runs)."""
    if not automatic_setup(user_xml, main_xml):
        return [f"{user_xml} turns automatic module setup off "
                "(<enableAutomaticTaskListDetermination> false). It is written for a C++ "
                "program that builds its own pipeline, such as X-SCAPE's test programs; "
                "runJetscape would create no module, run nothing and exit with success. Run "
                "it with its program from a source build, or set the element to true and "
                "name the modules in the XML"]
    lhapdf = sorted({line.strip() for el in ET.parse(user_xml).getroot().iter()
                     for line in (el.text or "").splitlines() if "LHAPDF6:" in line})
    if lhapdf:
        return [f"{user_xml} asks Pythia for LHAPDF6 sets:\n    " + "\n    ".join(lhapdf) +
                "\nThe wheel's Pythia has no LHAPDF6 plugin (and no LHAPDF sets but 3dMCGlauber's "
                "CT10nnlo); X-SCAPE would crash in Pythia's setup. Use Pythia's own PDFs "
                "(PDF:pSet = <number>), or a source build with LHAPDF"]
    gone = missing_modules(user_xml, main_xml)
    if gone:
        return [f"{user_xml} needs modules this xscape wheel does not have, and X-SCAPE "
                "would only warn and run without them:\n    " + "\n    ".join(gone) +
                "\nThe wheel is built without ROOT, HepMC, SMASH, FreestreamMilne, CLVisc, "
                "IPGlasma and the FNO hydro. Remove these from the XML, or use a source "
                "build or the production container"]
    return []


def cwd_problems(user_xml: str, cwd: str = ".") -> list[str]:
    """What the user XML reads relative to the working directory that ``cwd`` lacks."""
    user = ET.parse(user_xml).getroot()
    out = []
    if user.find("IS/MCGlauber") is not None and not os.path.isdir(os.path.join(cwd, "tables")):
        out.append("tables/ (3dMCGlauber's nucleon and valence-quark tables)")
    if user.find("Hydro/MUSIC") is not None and not os.path.isfile(os.path.join(cwd, "music_input")):
        out.append("music_input (MUSIC's input file)")
    for el in user.iter():
        text = (el.text or "").strip()
        if text.startswith("../") and not os.path.exists(os.path.join(cwd, text)):
            out.append(f"{text} (<{el.tag}>)")
    return out
