{ lib
, python3
, fetchFromGitHub
}:

python3.pkgs.buildPythonApplication rec {
  pname = "ai-toolbox-cockpit";
  version = "2026.9.24.1423";

  # Явно указываем формат сборки: pyproject.toml + setuptools.
  # Это требование nixpkgs 26.11 для Python-пакетов.
  pyproject = true;

  src = fetchFromGitHub {
    owner = "kyuz0";
    repo = "ai-toolbox-cockpit";
    rev = "e619c2cff5af4fa294cc1f7e1ed1590d7c505cb8";
    # Хеш-заглушка: Nix выдаст правильный при первой сборке.
    hash = "sha256-VmEkNQyGryryq1FYU72lM/dwc6tC7NEpR1ZlnC1nU5c=";
  };

  # Сборочная система (из pyproject.toml: requires = ["setuptools>=69"]).
  build-system = [
    python3.pkgs.setuptools
  ];

  # Runtime-зависимости (из pyproject.toml: dependencies).
  dependencies = with python3.pkgs; [
    textual
    huggingface-hub
    pyfiglet
  ];

  # Тесты не запускаем — они требуют сети и полного окружения.
  doCheck = false;

  meta = with lib; {
    description = "TUI for managing AI toolboxes, models, servers, and benchmarks";
    homepage = "https://github.com/kyuz0/ai-toolbox-cockpit";
    license = licenses.mit;
    mainProgram = "ai-toolbox-cockpit";
  };
}
