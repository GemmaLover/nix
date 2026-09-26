{ lib, python3, fetchFromGitHub, ... }:

python3.pkgs.buildPythonApplication rec {
  pname = "ai-toolbox-cockpit";
  version = "unstable-2026-09-26";

  src = fetchFromGitHub {
    owner = "kyuz0";
    repo = "ai-toolbox-cockpit";
    rev = "main";
    hash = lib.fakeHash;
  };

  propagatedBuildInputs = with python3.pkgs; [
    textual
    rich
  ];

  doCheck = false;

  meta = with lib; {
    description = "TUI for managing AI toolboxes";
    homepage = "https://github.com/kyuz0/ai-toolbox-cockpit";
    license = licenses.mit;
    mainProgram = "ai-toolbox-cockpit";
  };
}
