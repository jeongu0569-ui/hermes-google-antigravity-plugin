"""Hermes Antigravity import hook.

Installed as ``sitecustomize.py`` in the Hermes virtualenv.  It registers
import hooks that load ``antigravity_provider_patch`` at the points where
Hermes defines provider, auth, model-picker, runtime, auxiliary-client, and
WebUI registries.
"""

from __future__ import annotations

import os
import sys

_PATCHES_DIR = os.environ.get(
    "HERMES_PATCHES_DIR",
    os.path.expanduser("~/.hermes/patches"),
)

if os.path.isdir(_PATCHES_DIR) and _PATCHES_DIR not in sys.path:
    sys.path.insert(0, _PATCHES_DIR)


def _make_import_hook(target_module, patcher_fn, label):
    try:
        from importlib.abc import MetaPathFinder
        from importlib.util import find_spec
    except ImportError:
        return

    class _Finder(MetaPathFinder):
        _patched = False

        def find_spec(self, fullname, path=None, target=None):
            if fullname != target_module or self._patched:
                return None
            if self in sys.meta_path:
                sys.meta_path.remove(self)
            try:
                spec = find_spec(fullname)
            finally:
                if self not in sys.meta_path:
                    sys.meta_path.insert(0, self)
            if spec is None or spec.loader is None:
                return None
            original_exec = getattr(spec.loader, "exec_module", None)
            if not callable(original_exec):
                return None
            finder = self

            def patched_exec(module):
                original_exec(module)
                finder._patched = True
                try:
                    result = patcher_fn(module)
                    if isinstance(result, bool) and not result:
                        sys.stderr.write(
                            f"[{label}] patch declined; Hermes API may have changed\n"
                        )
                except Exception as exc:
                    sys.stderr.write(
                        f"[{label}] patch failed: {type(exc).__name__}: {exc}\n"
                    )

            spec.loader.exec_module = patched_exec
            return spec

    sys.meta_path.insert(0, _Finder())


def _patch_auth(_module):
    import antigravity_provider_patch

    antigravity_provider_patch._patch_auth_registry()
    antigravity_provider_patch._patch_providers()
    antigravity_provider_patch._patch_auxiliary_client()


def _patch_auth_commands(_module):
    import antigravity_provider_patch

    antigravity_provider_patch._patch_auth_registry()


def _patch_providers(_module):
    import antigravity_provider_patch

    antigravity_provider_patch.apply()


def _patch_commands(_module):
    import antigravity_provider_patch

    antigravity_provider_patch._patch_commands()


def _patch_cli(_module):
    import antigravity_provider_patch

    antigravity_provider_patch._patch_cli_agyquota()


def _patch_auxiliary(_module):
    import antigravity_provider_patch

    antigravity_provider_patch._patch_auth_registry()
    antigravity_provider_patch._patch_providers()
    antigravity_provider_patch._patch_auxiliary_client()


def _patch_runtime_provider(_module):
    import antigravity_provider_patch

    return antigravity_provider_patch._patch_runtime_provider()


def _patch_main(_module):
    import antigravity_provider_patch

    ok_models = antigravity_provider_patch._patch_models_module()
    ok_picker = antigravity_provider_patch._patch_model_picker()
    return bool(ok_models and ok_picker)


def _patch_model_switch(_module):
    import antigravity_provider_patch

    antigravity_provider_patch._patch_models_module()
    return antigravity_provider_patch._patch_model_switch_picker()


def _patch_webui_config(_module):
    import antigravity_provider_patch

    return antigravity_provider_patch._patch_webui_config()


try:
    _make_import_hook("hermes_cli.auth", _patch_auth, "hermes-antigravity-auth")
    _make_import_hook(
        "hermes_cli.auth_commands",
        _patch_auth_commands,
        "hermes-antigravity-auth-commands",
    )
    _make_import_hook("hermes_cli.providers", _patch_providers, "hermes-antigravity")
    _make_import_hook("hermes_cli.commands", _patch_commands, "hermes-antigravity-commands")
    _make_import_hook("cli", _patch_cli, "hermes-antigravity-cli")
    _make_import_hook(
        "agent.auxiliary_client",
        _patch_auxiliary,
        "hermes-antigravity-auxiliary",
    )
    _make_import_hook(
        "hermes_cli.runtime_provider",
        _patch_runtime_provider,
        "hermes-antigravity-runtime",
    )
    _make_import_hook("hermes_cli.main", _patch_main, "hermes-antigravity-main")
    _make_import_hook(
        "hermes_cli.model_switch",
        _patch_model_switch,
        "hermes-antigravity-model-switch",
    )
    _make_import_hook("api.config", _patch_webui_config, "hermes-antigravity-webui")
except Exception as exc:
    sys.stderr.write(f"[hermes-antigravity-sitecustomize] hook install failed: {exc}\n")
