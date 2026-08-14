#!/usr/bin/env python3
"""
Royalutil GUI - a Tkinter front-end for royalutil.sh, styled after Material 3.

Runs royalutil.sh in a real pseudo-terminal so sudo's password prompt works
normally, streams its output live, and drives it with the script's
--modules=<list> non-interactive mode (see royalutil.sh --help).

Requirements: Python 3 with tkinter (python3-tk on Debian/Ubuntu). No other
dependencies - everything else is Python's standard library, including the
Material 3 widgets below (cards, buttons, checkbox, switch, progress bar,
dialogs), which are drawn on tk.Canvas rather than pulled from a UI kit.
Linux only.
"""

import os
import pty
import re
import signal
import sys
import queue
import threading
import tkinter as tk
import tkinter.font as tkfont
from tkinter import scrolledtext

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROYALUTIL_SH = os.path.join(SCRIPT_DIR, "royalutil.sh")
LOG_FILE = os.path.join(os.path.expanduser("~"), "royalutil_setup.log")

ANSI_RE = re.compile(r"\x1b\[[0-9;]*[a-zA-Z]")
PROGRESS_RE = re.compile(r"Progress:.*?(\d+)%\s*\((\d+)/(\d+)\)")
PASSWORD_RE = re.compile(r"\[sudo\][^\n]*password|password[^\n]*:\s*$", re.IGNORECASE)

MODULES = [
    (1, "System Maintenance", "apt update && upgrade && autoremove"),
    (2, "Default Code Editor", "Set nano as EDITOR/VISUAL"),
    (3, "Git Setup", "Install git, set core.editor, identity"),
    (4, "Homebrew Setup", "Install Linuxbrew"),
    (5, "Zsh & Enhancements", "Install zsh, autosuggestions, syntax highlighting"),
    (6, "Flatpak Framework", "Install flatpak + Flathub remote"),
    (7, "Applications", "Bitwarden, VS Code, Firefox Nightly, Spotify, ..."),
    (8, "System Utilities", "fzf, fastfetch, btop, zellij, atuin"),
    (9, "Bootloader Themes", "Top-5-Bootloader-Themes"),
    (10, "Nerd Fonts", "JetBrainsMono Nerd Font"),
    (11, "Uninstall / Rollback", "Revert Royalutil's config changes"),
]

# ---------------------------------------------------------------------------
# App/tool catalog (config file: royalutil.conf, override with $ROYALUTIL_CONFIG).
# Same [flatpak]/[utilities] id|Name|Description format royalutil.sh reads, so
# the GUI and the shell script stay in sync from a single file. Selections made
# from this catalog are sent to the script via the ROYALUTIL_APPS /
# ROYALUTIL_UTILITIES env vars (see royalutil.sh --help).
# ---------------------------------------------------------------------------
CONFIG_FILE = os.environ.get("ROYALUTIL_CONFIG", os.path.join(SCRIPT_DIR, "royalutil.conf"))

DEFAULT_FLATPAK_CATALOG = [
    ("com.bitwarden.desktop", "Bitwarden", "Password manager"),
    ("com.visualstudio.code", "VS Code", "Code editor"),
    ("com.stremio.Stremio", "Stremio", "Media center / streaming"),
    ("io.github.flattool.Warehouse", "Warehouse", "Flatpak app manager"),
    ("io.github.getnf.Bazaar", "Bazaar", "Nerd Font manager"),
    ("org.mozilla.FirefoxNightly", "Firefox Nightly", "Web browser"),
]
DEFAULT_UTIL_CATALOG = [
    ("fzf", "fzf", "Fuzzy finder"),
    ("fastfetch", "fastfetch", "System info tool"),
    ("btop", "btop", "Resource monitor"),
    ("zellij", "zellij", "Terminal multiplexer"),
    ("atuin", "Atuin", "Shell history sync"),
]


def _parse_catalog_section(lines):
    items = []
    for line in lines:
        parts = line.split("|", 2)
        if len(parts) == 3:
            items.append((parts[0].strip(), parts[1].strip(), parts[2].strip()))
    return items


def load_catalog():
    """Returns (flatpak_items, utility_items), each a list of (id, name, desc)."""
    flatpak_lines, util_lines = [], []
    if os.path.isfile(CONFIG_FILE):
        section = None
        with open(CONFIG_FILE, "r", errors="replace") as f:
            for raw in f:
                stripped = raw.strip()
                if not stripped or stripped.startswith("#"):
                    continue
                if stripped.startswith("[") and stripped.endswith("]"):
                    section = stripped[1:-1].strip()
                    continue
                if section == "flatpak":
                    flatpak_lines.append(stripped)
                elif section == "utilities":
                    util_lines.append(stripped)
    flatpak = _parse_catalog_section(flatpak_lines) or DEFAULT_FLATPAK_CATALOG
    utilities = _parse_catalog_section(util_lines) or DEFAULT_UTIL_CATALOG
    return flatpak, utilities

# ---------------------------------------------------------------------------
# Material 3 design tokens (baseline purple scheme, light surface + a dark
# "surface" island for the console, mirroring how M3 apps keep code/output
# panels dark even in a light theme).
# ---------------------------------------------------------------------------
PRIMARY = "#6750A4"
ON_PRIMARY = "#FFFFFF"
PRIMARY_CONTAINER = "#EADDFF"
ON_PRIMARY_CONTAINER = "#21005D"
SECONDARY_CONTAINER = "#E8DEF8"
ON_SECONDARY_CONTAINER = "#1D192B"
SURFACE = "#FFFBFE"
SURFACE_CONTAINER_LOW = "#F7F2FA"
SURFACE_CONTAINER = "#F3EDF7"
SURFACE_CONTAINER_HIGH = "#ECE6F0"
SURFACE_CONTAINER_HIGHEST = "#E6E0E9"
ON_SURFACE = "#1C1B1F"
ON_SURFACE_VARIANT = "#49454F"
OUTLINE = "#79747E"
OUTLINE_VARIANT = "#CAC4D0"
ERROR = "#B3261E"
ON_ERROR = "#FFFFFF"

DARK_SURFACE = "#1C1B1F"
DARK_ON_SURFACE = "#E6E1E5"
DARK_PRIMARY = "#D0BCFF"

FONT_FAMILY = "TkDefaultFont"


def _resolve_font_family(root):
    fams = set(tkfont.families(root))
    for cand in ("Roboto", "Google Sans Text", "Noto Sans", "Ubuntu",
                 "Segoe UI", "Liberation Sans", "DejaVu Sans", "Helvetica"):
        if cand in fams:
            return cand
    return "TkDefaultFont"


def F(size, weight="normal"):
    return (FONT_FAMILY, size, weight)


def mix(hex1, hex2, t):
    """Blend two #rrggbb colors; t=0 -> hex1, t=1 -> hex2."""
    h1 = hex1.lstrip("#")
    h2 = hex2.lstrip("#")
    r1, g1, b1 = int(h1[0:2], 16), int(h1[2:4], 16), int(h1[4:6], 16)
    r2, g2, b2 = int(h2[0:2], 16), int(h2[2:4], 16), int(h2[4:6], 16)
    r = int(r1 + (r2 - r1) * t)
    g = int(g1 + (g2 - g1) * t)
    b = int(b1 + (b2 - b1) * t)
    return f"#{r:02x}{g:02x}{b:02x}"


def rounded_rect(canvas, x1, y1, x2, y2, r, **kw):
    r = max(0, min(r, (x2 - x1) / 2, (y2 - y1) / 2))
    points = [
        x1 + r, y1, x2 - r, y1, x2, y1, x2, y1 + r,
        x2, y2 - r, x2, y2, x2 - r, y2, x1 + r, y2,
        x1, y2, x1, y2 - r, x1, y1 + r, x1, y1,
    ]
    return canvas.create_polygon(points, smooth=True, **kw)


# ---------------------------------------------------------------------------
# Material 3 widgets
# ---------------------------------------------------------------------------

class Card(tk.Frame):
    """A rounded, filled surface container. Put content in `.inner`."""

    def __init__(self, parent, fill, radius=20, pad=16):
        outer_bg = parent.cget("bg")
        super().__init__(parent, bg=outer_bg, highlightthickness=0, bd=0)
        self.fill = fill
        self.radius = radius
        self.canvas = tk.Canvas(self, bg=outer_bg, highlightthickness=0, bd=0)
        self.canvas.pack(fill="both", expand=True)
        self.body = tk.Frame(self.canvas, bg=fill)
        self._win = self.canvas.create_window(radius, radius, window=self.body, anchor="nw")
        self.inner = tk.Frame(self.body, bg=fill, padx=pad, pady=pad)
        self.inner.pack(fill="both", expand=True)
        self.canvas.bind("<Configure>", self._on_resize)
        # A canvas doesn't propagate the size of items placed on it via
        # create_window, so without this the canvas keeps Tk's default
        # ~200x150 request no matter what's packed into .inner later (e.g. a
        # dialog's title/message/list/buttons, added by the caller after
        # Card() returns). That leaves the toplevel too small to show
        # content packed after an expanding sibling, like a button row.
        # Track .inner's actual required size and feed it back as the
        # canvas's minimum request so the window opens tall/wide enough.
        self.inner.bind("<Configure>", self._on_inner_resize)

    def _on_inner_resize(self, event):
        r = self.radius
        self.canvas.configure(width=self.inner.winfo_reqwidth() + 2 * r,
                               height=self.inner.winfo_reqheight() + 2 * r)

    def _on_resize(self, event):
        w, h = event.width, event.height
        r = self.radius
        bw = max(w - 2 * r, 10)
        bh = max(h - 2 * r, 10)
        self.canvas.delete("shape")
        rounded_rect(self.canvas, 0, 0, w, h, r, fill=self.fill, outline="", tags="shape")
        self.canvas.tag_lower("shape")
        self.canvas.coords(self._win, r, r)
        self.canvas.itemconfig(self._win, width=bw, height=bh)


class MDButton(tk.Canvas):
    """Material 3 button: filled / tonal / outlined / text / danger."""

    def __init__(self, parent, text, command=None, variant="filled",
                 width=120, height=40, font=None, state="normal"):
        parent_bg = parent.cget("bg")
        super().__init__(parent, width=width, height=height, bg=parent_bg,
                          highlightthickness=0, bd=0, cursor="hand2")
        self.command = command
        self.variant = variant
        self.text = text
        self.font = font or F(11, "bold")
        self._state = state
        self._hover = False
        self._press = False
        self.parent_bg = parent_bg
        self._resolve_colors()
        self.bind("<Enter>", self._on_enter)
        self.bind("<Leave>", self._on_leave)
        self.bind("<ButtonPress-1>", self._on_press)
        self.bind("<ButtonRelease-1>", self._on_release)
        self.bind("<Configure>", lambda e: self._draw())
        self._draw()

    def _resolve_colors(self):
        v = self.variant
        if v == "filled":
            self.base_fill, self.fg, self.border = PRIMARY, ON_PRIMARY, None
        elif v == "tonal":
            self.base_fill, self.fg, self.border = SECONDARY_CONTAINER, ON_SECONDARY_CONTAINER, None
        elif v == "outlined":
            self.base_fill, self.fg, self.border = self.parent_bg, PRIMARY, OUTLINE
        elif v == "danger":
            self.base_fill, self.fg, self.border = ERROR, ON_ERROR, None
        else:  # text
            self.base_fill, self.fg, self.border = self.parent_bg, PRIMARY, None

    def set_state(self, state):
        self._state = state
        self._hover = False
        self._press = False
        self._draw()

    def _current_fill(self):
        if self._state == "disabled":
            return mix(self.parent_bg, ON_SURFACE, 0.06)
        fill = self.base_fill
        tint = "#000000" if self.variant in ("filled", "tonal", "danger") else PRIMARY
        if self._press:
            fill = mix(fill, tint, 0.16)
        elif self._hover:
            fill = mix(fill, tint, 0.08)
        return fill

    def _draw(self):
        self.delete("all")
        w = self.winfo_width() or int(self["width"])
        h = self.winfo_height() or int(self["height"])
        r = h // 2
        fill = self._current_fill()
        disabled = self._state == "disabled"
        outline = self.border if (self.border and not disabled) else ""
        rounded_rect(self, 1, 1, w - 1, h - 1, r, fill=fill, outline=outline, width=1.4)
        fg = self.fg if not disabled else mix(self.parent_bg, ON_SURFACE, 0.38)
        self.create_text(w // 2, h // 2, text=self.text, fill=fg, font=self.font)

    def _on_enter(self, e):
        if self._state != "disabled":
            self._hover = True
            self._draw()

    def _on_leave(self, e):
        self._hover = False
        self._press = False
        self._draw()

    def _on_press(self, e):
        if self._state != "disabled":
            self._press = True
            self._draw()

    def _on_release(self, e):
        was = self._press
        self._press = False
        self._draw()
        if was and self._state != "disabled" and self.command:
            if 0 <= e.x <= self.winfo_width() and 0 <= e.y <= self.winfo_height():
                self.command()


class MDCheckbox(tk.Canvas):
    def __init__(self, parent, variable, size=20, command=None):
        parent_bg = parent.cget("bg")
        super().__init__(parent, width=size, height=size, bg=parent_bg,
                          highlightthickness=0, bd=0, cursor="hand2")
        self.var = variable
        self.size = size
        self.command = command
        self.bind("<Button-1>", self.toggle)
        self._draw()

    def toggle(self, e=None):
        self.var.set(not self.var.get())
        self._draw()
        if self.command:
            self.command()

    def _draw(self):
        self.delete("all")
        s = self.size
        on = self.var.get()
        bg = self.cget("bg")
        fill = PRIMARY if on else bg
        outline = "" if on else OUTLINE
        rounded_rect(self, 1.5, 1.5, s - 1.5, s - 1.5, 4, fill=fill, outline=outline, width=1.6)
        if on:
            self.create_line(s * 0.27, s * 0.53, s * 0.43, s * 0.70, s * 0.75, s * 0.32,
                              fill=ON_PRIMARY, width=2, capstyle="round", joinstyle="round")

    def refresh(self):
        self._draw()


class MDSwitch(tk.Canvas):
    def __init__(self, parent, variable, command=None, width=48, height=28):
        parent_bg = parent.cget("bg")
        super().__init__(parent, width=width, height=height, bg=parent_bg,
                          highlightthickness=0, bd=0, cursor="hand2")
        self.var = variable
        self.command = command
        self.bind("<Button-1>", self._toggle)
        self.bind("<Configure>", lambda e: self._draw())
        self._draw()

    def _toggle(self, e=None):
        self.var.set(not self.var.get())
        self._draw()
        if self.command:
            self.command()

    def _draw(self):
        self.delete("all")
        w = self.winfo_width() or int(self["width"])
        h = self.winfo_height() or int(self["height"])
        on = self.var.get()
        track_fill = PRIMARY if on else SURFACE_CONTAINER_HIGHEST
        track_outline = "" if on else OUTLINE
        rounded_rect(self, 1, 1, w - 1, h - 1, h // 2, fill=track_fill, outline=track_outline, width=1.2)
        pad = 4
        knob_r = (h - 2 * pad) // 2 if on else (h - 2 * pad - 4) // 2
        knob_fill = ON_PRIMARY if on else OUTLINE
        cx = w - h // 2 if on else h // 2
        cy = h // 2
        self.create_oval(cx - knob_r, cy - knob_r, cx + knob_r, cy + knob_r, fill=knob_fill, outline="")


class MDProgressBar(tk.Canvas):
    def __init__(self, parent, height=8):
        parent_bg = parent.cget("bg")
        super().__init__(parent, height=height, bg=parent_bg, highlightthickness=0, bd=0)
        self.value = 0
        self.bind("<Configure>", lambda e: self._draw())
        self._draw()

    def set(self, pct):
        self.value = max(0, min(100, pct))
        self._draw()

    def _draw(self):
        self.delete("all")
        w = self.winfo_width() or 300
        h = self.winfo_height() or int(self["height"])
        r = h / 2
        rounded_rect(self, 0, 0, w, h, r, fill=SURFACE_CONTAINER_HIGHEST, outline="")
        if self.value > 0:
            fw = max(h, w * self.value / 100)
            rounded_rect(self, 0, 0, fw, h, r, fill=PRIMARY, outline="")


class MDEntry(tk.Frame):
    def __init__(self, parent, textvariable, radius=10, height=40, show=None, state="normal"):
        parent_bg = parent.cget("bg")
        super().__init__(parent, bg=parent_bg)
        self.canvas = tk.Canvas(self, bg=parent_bg, highlightthickness=0, bd=0, height=height)
        self.canvas.pack(fill="x", expand=True)
        self.radius = radius
        self.entry = tk.Entry(
            self.canvas, textvariable=textvariable, relief="flat",
            bg=SURFACE_CONTAINER_LOW, fg=ON_SURFACE, insertbackground=ON_SURFACE,
            disabledbackground=SURFACE_CONTAINER_LOW, disabledforeground=OUTLINE,
            font=F(10), bd=0, highlightthickness=0,
        )
        if show:
            self.entry.config(show=show)
        if state != "normal":
            self.entry.config(state=state)
        self._win = self.canvas.create_window(radius, 6, window=self.entry, anchor="nw")
        self.canvas.bind("<Configure>", self._draw)
        self.entry.bind("<FocusIn>", lambda e: self._draw())
        self.entry.bind("<FocusOut>", lambda e: self._draw())

    def set_state(self, state):
        self.entry.config(state=state)

    def _draw(self, event=None):
        w = self.canvas.winfo_width() or 200
        h = self.canvas.winfo_height() or 40
        self.canvas.delete("border")
        try:
            focused = self.entry is self.focus_get_safe()
        except Exception:
            focused = False
        outline = PRIMARY if focused else OUTLINE
        width = 2 if focused else 1
        rounded_rect(self.canvas, 1, 1, w - 1, h - 1, self.radius, fill=SURFACE_CONTAINER_LOW,
                      outline=outline, width=width, tags="border")
        self.canvas.tag_lower("border")
        self.canvas.coords(self._win, self.radius, 6)
        self.canvas.itemconfig(self._win, width=max(w - 2 * self.radius, 10))

    def focus_get_safe(self):
        try:
            return self.entry.focus_get()
        except Exception:
            return None


class VScrollFrame(tk.Frame):
    """A vertically scrollable area; put content in `.inner`."""

    def __init__(self, parent, bg, height=None):
        super().__init__(parent, bg=bg)
        self.canvas = tk.Canvas(self, bg=bg, highlightthickness=0, bd=0)
        if height:
            self.canvas.configure(height=height)
        self.vbar = tk.Scrollbar(self, orient="vertical", command=self.canvas.yview,
                                  bg=OUTLINE_VARIANT, troughcolor=bg, activebackground=PRIMARY,
                                  highlightthickness=0, bd=0, width=10,
                                  elementborderwidth=0)
        self.canvas.configure(yscrollcommand=self.vbar.set)
        self.canvas.pack(side="left", fill="both", expand=True)
        self.vbar.pack(side="right", fill="y")
        self.inner = tk.Frame(self.canvas, bg=bg)
        self._win = self.canvas.create_window(0, 0, window=self.inner, anchor="nw")
        self.inner.bind("<Configure>", lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all")))
        self.canvas.bind("<Configure>", lambda e: self.canvas.itemconfig(self._win, width=e.width))
        self.canvas.bind("<Enter>", self._bind_wheel)
        self.canvas.bind("<Leave>", self._unbind_wheel)

    def _bind_wheel(self, e):
        self.canvas.bind_all("<MouseWheel>", self._on_wheel)
        self.canvas.bind_all("<Button-4>", self._on_wheel)
        self.canvas.bind_all("<Button-5>", self._on_wheel)

    def _unbind_wheel(self, e):
        self.canvas.unbind_all("<MouseWheel>")
        self.canvas.unbind_all("<Button-4>")
        self.canvas.unbind_all("<Button-5>")

    def _on_wheel(self, e):
        if getattr(e, "num", None) == 4:
            self.canvas.yview_scroll(-1, "units")
        elif getattr(e, "num", None) == 5:
            self.canvas.yview_scroll(1, "units")
        else:
            self.canvas.yview_scroll(int(-1 * (e.delta / 120)), "units")


class MDDialog(tk.Toplevel):
    """A Material 3 basic dialog: headline, supporting text, optional text
    field, and up to three actions (Cancel / secondary / primary). Blocks
    until closed (modal)."""

    def __init__(self, parent, title, message, items=None, entry=False, password=False,
                 ok_text="OK", show_cancel=True, danger=False,
                 secondary_text=None, secondary_danger=False):
        super().__init__(parent)
        self.result = None
        self.confirmed = False
        self.choice = None  # "ok" | "secondary" | "cancel"
        self.configure(bg=SURFACE)
        self.title(title)
        self.transient(parent)
        self.resizable(True, True)
        self.protocol("WM_DELETE_WINDOW", self._cancel)

        card = Card(self, fill=SURFACE_CONTAINER_HIGH, radius=24, pad=24)
        card.pack(fill="both", expand=True, padx=12, pady=12)

        tk.Label(card.inner, text=title, font=F(16, "bold"), bg=SURFACE_CONTAINER_HIGH,
                 fg=ON_SURFACE, anchor="w", justify="left", wraplength=320).pack(fill="x")
        tk.Label(card.inner, text=message, font=F(10), bg=SURFACE_CONTAINER_HIGH,
                 fg=ON_SURFACE_VARIANT, anchor="w", justify="left", wraplength=320).pack(
            fill="x", pady=(8, 12 if items else 16))

        if items:
            list_frame = tk.Frame(card.inner, bg=SURFACE_CONTAINER_HIGH)
            list_frame.pack(fill="both", expand=True, pady=(0, 16))
            list_text = tk.Text(
                list_frame, wrap="word", font=F(9), bg=SURFACE_CONTAINER_HIGHEST,
                fg=ON_SURFACE, bd=0, highlightthickness=0, height=7, width=34,
                relief="flat", padx=10, pady=8, cursor="arrow",
            )
            list_vbar = tk.Scrollbar(
                list_frame, orient="vertical", command=list_text.yview,
                bg=OUTLINE_VARIANT, troughcolor=SURFACE_CONTAINER_HIGH,
                activebackground=PRIMARY, bd=0, width=10, highlightthickness=0,
                elementborderwidth=0,
            )
            list_text.configure(yscrollcommand=list_vbar.set)
            list_text.pack(side="left", fill="both", expand=True)
            list_vbar.pack(side="right", fill="y")
            list_text.insert("1.0", "\n".join(f"• {it}" for it in items))
            list_text.config(state="disabled")

        self.var = tk.StringVar()
        if entry:
            field = MDEntry(card.inner, textvariable=self.var, show="*" if password else None)
            field.pack(fill="x", pady=(0, 4))
            field.entry.focus_set()
            field.entry.bind("<Return>", lambda e: self._ok())

        btn_row = tk.Frame(card.inner, bg=SURFACE_CONTAINER_HIGH)
        btn_row.pack(fill="x", pady=(16, 0))
        MDButton(btn_row, ok_text, command=self._ok,
                 variant="danger" if danger else "filled",
                 width=100, height=38, font=F(10, "bold")).pack(side="right")
        if secondary_text:
            MDButton(btn_row, secondary_text, command=self._secondary,
                      variant="danger" if secondary_danger else "outlined",
                      width=130, height=38, font=F(10, "bold")).pack(side="right", padx=(0, 8))
        if show_cancel:
            MDButton(btn_row, "Cancel", command=self._cancel, variant="text",
                      width=90, height=38, font=F(10, "bold")).pack(side="right", padx=(0, 8))

        self.grab_set()
        self.update_idletasks()
        # Never let the window shrink smaller than its content needs (e.g. the
        # 3-button row), but resizable=True still lets a user grow it further
        # if their screen/font settings need more room.
        self.minsize(self.winfo_reqwidth(), self.winfo_reqheight())
        self._center(parent)
        self.wait_window(self)

    def _center(self, parent):
        self.update_idletasks()
        w, h = self.winfo_width(), self.winfo_height()
        sw, sh = self.winfo_screenwidth(), self.winfo_screenheight()
        try:
            pw, ph = parent.winfo_width(), parent.winfo_height()
            px, py = parent.winfo_rootx(), parent.winfo_rooty()
            x = px + (pw - w) // 2
            y = py + (ph - h) // 2
        except tk.TclError:
            x = (sw - w) // 2
            y = (sh - h) // 2
        # Clamp fully on-screen so buttons never end up off the visible desktop.
        x = max(0, min(x, sw - w))
        y = max(0, min(y, sh - h))
        self.geometry(f"+{x}+{y}")

    def _ok(self):
        self.confirmed = True
        self.choice = "ok"
        self.result = self.var.get()
        self.destroy()

    def _secondary(self):
        self.confirmed = True
        self.choice = "secondary"
        self.result = self.var.get()
        self.destroy()

    def _cancel(self):
        self.confirmed = False
        self.choice = "cancel"
        self.result = None
        self.destroy()


def md_confirm(parent, title, message, items=None, ok_text="Continue", danger=False):
    d = MDDialog(parent, title, message, items=items, ok_text=ok_text, danger=danger)
    return d.confirmed


def md_confirm_run(parent, title, message, items, dry_run):
    """Preview/confirm dialog for a run. When dry_run is True, the primary
    button previews and a red 'Run for Real' button lets the user commit to
    the actual run right from the preview, no need to cancel, flip the Dry
    Run switch, and reopen the dialog. When dry_run is False, the primary
    button runs for real and a 'Preview Instead' button offers an escape
    hatch back to a safe dry run. Returns 'run', 'preview', or None (cancelled)."""
    if dry_run:
        d = MDDialog(parent, title, message, items=items,
                     ok_text="Preview", secondary_text="Run for Real", secondary_danger=True)
        if not d.confirmed:
            return None
        return "run" if d.choice == "secondary" else "preview"
    else:
        d = MDDialog(parent, title, message, items=items,
                     ok_text="Run", danger=True, secondary_text="Preview Instead")
        if not d.confirmed:
            return None
        return "preview" if d.choice == "secondary" else "run"


def md_alert(parent, title, message):
    MDDialog(parent, title, message, show_cancel=False, ok_text="OK")


def md_prompt_password(parent, title, message):
    d = MDDialog(parent, title, message, entry=True, password=True, ok_text="OK")
    return d.result if d.confirmed else None


# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------

class TerminalConsole:
    """Feeds raw child-process output into a Text widget, honoring \\r line
    overwrites (progress bars) the way a real terminal would, and stripping
    ANSI color/cursor codes."""

    def __init__(self, text_widget):
        self.text = text_widget

    def feed(self, chunk):
        chunk = ANSI_RE.sub("", chunk)
        for part in re.split(r"(\r\n|\r|\n)", chunk):
            if part == "":
                continue
            if part in ("\n", "\r\n"):
                self.text.insert("end", "\n")
            elif part == "\r":
                self._clear_last_line()
            else:
                self.text.insert("end", part)
        self.text.see("end")

    def _clear_last_line(self):
        last_line_start = self.text.index("end-1c linestart")
        self.text.delete(last_line_start, "end-1c")


class RoyalutilGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("Royalutil")
        self.root.geometry("1060x860")
        self.root.minsize(920, 700)
        self.root.configure(bg=SURFACE)

        self.master_fd = None
        self.child_pid = None
        self.reader_thread = None
        self.event_queue = queue.Queue()
        self.awaiting_password = False
        self.running = False

        self.module_vars = {}
        self.app_vars = {}
        self.util_vars = {}
        self.dry_run_var = tk.BooleanVar(value=True)
        self.git_name_var = tk.StringVar()
        self.git_email_var = tk.StringVar()

        self._build_ui()
        self._check_script_present()
        self.root.after(50, self._poll_queue)

    # ---------- UI ----------

    def _build_ui(self):
        self._build_topbar()

        body = tk.Frame(self.root, bg=SURFACE)
        body.pack(fill="both", expand=True, padx=20, pady=(16, 20))
        body.columnconfigure(0, weight=0)
        body.columnconfigure(1, weight=1)
        body.rowconfigure(0, weight=1)

        left_outer = tk.Frame(body, bg=SURFACE, width=360)
        left_outer.grid(row=0, column=0, sticky="nsew", padx=(0, 16))
        left_outer.grid_propagate(False)
        left_scroll = VScrollFrame(left_outer, bg=SURFACE)
        left_scroll.pack(fill="both", expand=True)
        left = left_scroll.inner

        self._build_modules_card(left)
        self._build_catalog_card(left)
        self._build_git_card(left)
        self._build_options_card(left)
        self._build_actions(left)

        right = tk.Frame(body, bg=SURFACE)
        right.grid(row=0, column=1, sticky="nsew")
        right.rowconfigure(1, weight=1)
        right.columnconfigure(0, weight=1)

        self._build_progress_card(right)
        self._build_console_card(right)

    def _build_topbar(self):
        bar = tk.Frame(self.root, bg=SURFACE, height=64)
        bar.pack(fill="x", side="top")
        bar.pack_propagate(False)
        inner = tk.Frame(bar, bg=SURFACE)
        inner.pack(fill="both", expand=True, padx=24)
        tk.Label(inner, text="👑", font=F(22), bg=SURFACE, fg=PRIMARY).pack(side="left", pady=10)
        title_col = tk.Frame(inner, bg=SURFACE)
        title_col.pack(side="left", padx=(10, 0))
        tk.Label(title_col, text="Royalutil", font=F(18, "bold"), bg=SURFACE,
                 fg=ON_SURFACE, anchor="w").pack(anchor="w")
        tk.Label(title_col, text="Interactive Linux setup utility", font=F(9), bg=SURFACE,
                 fg=ON_SURFACE_VARIANT, anchor="w").pack(anchor="w")
        tk.Frame(self.root, bg=OUTLINE_VARIANT, height=1).pack(fill="x", side="top")

    def _section_label(self, parent, text, fill):
        tk.Label(parent, text=text, font=F(13, "bold"), bg=fill, fg=ON_SURFACE,
                 anchor="w").pack(side="left")

    def _build_modules_card(self, parent):
        card = Card(parent, fill=SURFACE_CONTAINER, radius=20, pad=16)
        card.pack(fill="x", pady=(0, 14))

        header = tk.Frame(card.inner, bg=SURFACE_CONTAINER)
        header.pack(fill="x")
        self._section_label(header, "Modules", SURFACE_CONTAINER)
        btns = tk.Frame(header, bg=SURFACE_CONTAINER)
        btns.pack(side="right")
        MDButton(btns, "All", command=self._select_all, variant="text",
                 width=44, height=28, font=F(9, "bold")).pack(side="left")
        MDButton(btns, "None", command=self._select_none, variant="text",
                 width=54, height=28, font=F(9, "bold")).pack(side="left")

        scroll = VScrollFrame(card.inner, bg=SURFACE_CONTAINER, height=340)
        scroll.pack(fill="both", expand=True, pady=(8, 0))

        for num, name, desc in MODULES:
            self._build_module_row(scroll.inner, num, name, desc)

    def _build_module_row(self, parent, num, name, desc):
        var = tk.BooleanVar(value=False)
        self.module_vars[num] = var

        row = tk.Frame(parent, bg=SURFACE_CONTAINER)
        row.pack(fill="x", pady=1)
        cb = MDCheckbox(row, variable=var, size=20)
        cb.pack(side="left", padx=(4, 10), pady=8)
        text_col = tk.Frame(row, bg=SURFACE_CONTAINER)
        text_col.pack(side="left", fill="x", expand=True)
        name_lbl = tk.Label(text_col, text=f"{num}. {name}", font=F(10, "bold"),
                             bg=SURFACE_CONTAINER, fg=ON_SURFACE, anchor="w")
        name_lbl.pack(fill="x")
        desc_lbl = tk.Label(text_col, text=desc, font=F(8), bg=SURFACE_CONTAINER,
                             fg=ON_SURFACE_VARIANT, anchor="w", wraplength=200, justify="left")
        desc_lbl.pack(fill="x")

        widgets = (row, text_col, name_lbl, desc_lbl)

        def toggle(e):
            cb.toggle()

        def enter(e):
            for w in widgets:
                w.configure(bg=SURFACE_CONTAINER_HIGH)
            cb.configure(bg=SURFACE_CONTAINER_HIGH)
            cb.refresh()

        def leave(e):
            for w in widgets:
                w.configure(bg=SURFACE_CONTAINER)
            cb.configure(bg=SURFACE_CONTAINER)
            cb.refresh()

        for w in widgets:
            w.bind("<Button-1>", toggle)
            w.bind("<Enter>", enter)
            w.bind("<Leave>", leave)

    def _build_catalog_card(self, parent):
        flatpak_items, util_items = load_catalog()

        card = Card(parent, fill=SURFACE_CONTAINER, radius=20, pad=16)
        card.pack(fill="x", pady=(0, 14))

        header = tk.Frame(card.inner, bg=SURFACE_CONTAINER)
        header.pack(fill="x")
        self._section_label(header, "App & Tool Catalog", SURFACE_CONTAINER)

        tk.Label(card.inner, text=f"Pick individual items, then Install Selected. "
                                    f"Add more by editing {os.path.basename(CONFIG_FILE)}.",
                 font=F(8), bg=SURFACE_CONTAINER, fg=ON_SURFACE_VARIANT, anchor="w",
                 justify="left", wraplength=290).pack(fill="x", pady=(2, 8))

        scroll = VScrollFrame(card.inner, bg=SURFACE_CONTAINER, height=260)
        scroll.pack(fill="both", expand=True)

        self._build_catalog_section(scroll.inner, "Applications (Flatpak)", flatpak_items, self.app_vars)
        self._build_catalog_section(scroll.inner, "Utilities", util_items, self.util_vars)

        self.install_btn = MDButton(card.inner, "Install Selected", command=self._on_install_selected,
                                     variant="tonal", height=40, font=F(10, "bold"))
        self.install_btn.pack(fill="x", pady=(10, 0))

    def _build_catalog_section(self, parent, title, items, vars_dict):
        bg = parent.cget("bg")
        header = tk.Frame(parent, bg=bg)
        header.pack(fill="x", pady=(6, 2))
        tk.Label(header, text=title, font=F(9, "bold"), bg=bg, fg=ON_SURFACE_VARIANT,
                 anchor="w").pack(side="left")
        btns = tk.Frame(header, bg=bg)
        btns.pack(side="right")
        MDButton(btns, "All", command=lambda: self._set_all(vars_dict, True), variant="text",
                 width=40, height=24, font=F(8, "bold")).pack(side="left")
        MDButton(btns, "None", command=lambda: self._set_all(vars_dict, False), variant="text",
                 width=50, height=24, font=F(8, "bold")).pack(side="left")

        for item_id, name, desc in items:
            self._build_catalog_row(parent, item_id, name, desc, vars_dict)

    def _build_catalog_row(self, parent, item_id, name, desc, vars_dict):
        var = tk.BooleanVar(value=False)
        vars_dict[item_id] = var
        bg = parent.cget("bg")

        row = tk.Frame(parent, bg=bg)
        row.pack(fill="x", pady=1)
        cb = MDCheckbox(row, variable=var, size=18)
        cb.pack(side="left", padx=(4, 10), pady=6)
        text_col = tk.Frame(row, bg=bg)
        text_col.pack(side="left", fill="x", expand=True)
        name_lbl = tk.Label(text_col, text=name, font=F(9, "bold"), bg=bg,
                             fg=ON_SURFACE, anchor="w")
        name_lbl.pack(fill="x")
        desc_lbl = tk.Label(text_col, text=desc, font=F(8), bg=bg,
                             fg=ON_SURFACE_VARIANT, anchor="w", wraplength=200, justify="left")
        desc_lbl.pack(fill="x")

        widgets = (row, text_col, name_lbl, desc_lbl)

        def toggle(e):
            cb.toggle()

        def enter(e):
            for w in widgets:
                w.configure(bg=SURFACE_CONTAINER_HIGH)
            cb.configure(bg=SURFACE_CONTAINER_HIGH)
            cb.refresh()

        def leave(e):
            for w in widgets:
                w.configure(bg=bg)
            cb.configure(bg=bg)
            cb.refresh()

        for w in widgets:
            w.bind("<Button-1>", toggle)
            w.bind("<Enter>", enter)
            w.bind("<Leave>", leave)

    def _build_git_card(self, parent):
        card = Card(parent, fill=SURFACE_CONTAINER_LOW, radius=20, pad=16)
        card.pack(fill="x", pady=(0, 14))
        self._section_label(card.inner, "Git identity", SURFACE_CONTAINER_LOW)
        tk.Label(card.inner, text="Optional — used only by module 3 (Git Setup). "
                                    "Leave blank to skip identity config.",
                 font=F(8), bg=SURFACE_CONTAINER_LOW, fg=ON_SURFACE_VARIANT,
                 anchor="w", justify="left", wraplength=290).pack(fill="x", pady=(4, 10))
        tk.Label(card.inner, text="Name", font=F(8, "bold"), bg=SURFACE_CONTAINER_LOW,
                 fg=ON_SURFACE_VARIANT, anchor="w").pack(fill="x")
        MDEntry(card.inner, textvariable=self.git_name_var).pack(fill="x", pady=(2, 8))
        tk.Label(card.inner, text="Email", font=F(8, "bold"), bg=SURFACE_CONTAINER_LOW,
                 fg=ON_SURFACE_VARIANT, anchor="w").pack(fill="x")
        MDEntry(card.inner, textvariable=self.git_email_var).pack(fill="x", pady=(2, 0))

    def _build_options_card(self, parent):
        card = Card(parent, fill=SURFACE_CONTAINER_LOW, radius=20, pad=16)
        card.pack(fill="x", pady=(0, 14))
        self._section_label(card.inner, "Options", SURFACE_CONTAINER_LOW)
        row = tk.Frame(card.inner, bg=SURFACE_CONTAINER_LOW)
        row.pack(fill="x", pady=(10, 0))
        text_col = tk.Frame(row, bg=SURFACE_CONTAINER_LOW)
        text_col.pack(side="left", fill="x", expand=True)
        tk.Label(text_col, text="Dry run", font=F(10, "bold"), bg=SURFACE_CONTAINER_LOW,
                 fg=ON_SURFACE, anchor="w").pack(fill="x")
        tk.Label(text_col, text="Preview actions, change nothing", font=F(8),
                 bg=SURFACE_CONTAINER_LOW, fg=ON_SURFACE_VARIANT, anchor="w").pack(fill="x")
        MDSwitch(row, variable=self.dry_run_var).pack(side="right")

    def _build_actions(self, parent):
        row = tk.Frame(parent, bg=SURFACE)
        row.pack(fill="x")
        self.run_btn = MDButton(row, "Run", command=self._on_run, variant="filled",
                                 width=300, height=46, font=F(12, "bold"))
        self.run_btn.pack(fill="x")
        sub_row = tk.Frame(row, bg=SURFACE)
        sub_row.pack(fill="x", pady=(10, 0))
        sub_row.columnconfigure(0, weight=1)
        sub_row.columnconfigure(1, weight=1)
        self.cancel_btn = MDButton(sub_row, "Cancel", command=self._on_cancel,
                                    variant="outlined", height=38, font=F(10, "bold"),
                                    state="disabled")
        self.cancel_btn.grid(row=0, column=0, sticky="ew", padx=(0, 6))
        self.log_btn = MDButton(sub_row, "Open Log", command=self._open_log,
                                 variant="text", height=38, font=F(10, "bold"))
        self.log_btn.grid(row=0, column=1, sticky="ew", padx=(6, 0))

    def _build_progress_card(self, parent):
        card = Card(parent, fill=SURFACE_CONTAINER_LOW, radius=20, pad=16)
        card.grid(row=0, column=0, sticky="ew", pady=(0, 14))
        header = tk.Frame(card.inner, bg=SURFACE_CONTAINER_LOW)
        header.pack(fill="x")
        self._section_label(header, "Progress", SURFACE_CONTAINER_LOW)
        self.status_label = tk.Label(header, text="Idle", font=F(9), bg=SURFACE_CONTAINER_LOW,
                                      fg=ON_SURFACE_VARIANT)
        self.status_label.pack(side="right")
        self.progress = MDProgressBar(card.inner, height=8)
        self.progress.pack(fill="x", pady=(10, 0))

    def _build_console_card(self, parent):
        card = Card(parent, fill=DARK_SURFACE, radius=20, pad=12)
        card.grid(row=1, column=0, sticky="nsew")
        card.inner.pack_configure(fill="both", expand=True)

        self.console = scrolledtext.ScrolledText(
            card.inner, bg=DARK_SURFACE, fg=DARK_ON_SURFACE, insertbackground=DARK_PRIMARY,
            selectbackground=mix(DARK_SURFACE, DARK_PRIMARY, 0.35), relief="flat",
            font=("Monospace", 10), wrap="word", state="normal", bd=0, highlightthickness=0,
        )
        self.console.pack(fill="both", expand=True)
        self.terminal = TerminalConsole(self.console)

        input_row = tk.Frame(parent, bg=SURFACE)
        input_row.grid(row=2, column=0, sticky="ew", pady=(10, 0))
        input_row.columnconfigure(0, weight=1)
        self.input_var = tk.StringVar()
        self.input_entry = MDEntry(input_row, textvariable=self.input_var, height=38, state="disabled")
        self.input_entry.grid(row=0, column=0, sticky="ew")
        self.input_entry.entry.bind("<Return>", lambda e: self._send_input())
        self.send_btn = MDButton(input_row, "Send", command=self._send_input, variant="tonal",
                                  width=90, height=38, font=F(9, "bold"), state="disabled")
        self.send_btn.grid(row=0, column=1, padx=(8, 0))
        tk.Label(parent, text="(only needed if the script asks something unexpected)",
                 font=F(8), bg=SURFACE, fg=ON_SURFACE_VARIANT).grid(
            row=3, column=0, sticky="w", pady=(4, 0))

    def _check_script_present(self):
        if not os.path.isfile(ROYALUTIL_SH):
            md_alert(self.root, "royalutil.sh not found",
                     f"Expected to find royalutil.sh next to this GUI:\n{ROYALUTIL_SH}")
            self.run_btn.set_state("disabled")
            self.install_btn.set_state("disabled")

    def _select_all(self):
        self._set_all(self.module_vars, True)

    def _select_none(self):
        self._set_all(self.module_vars, False)

    def _set_all(self, vars_dict, value):
        for var in vars_dict.values():
            var.set(value)
        self._refresh_checkboxes()

    def _refresh_checkboxes(self):
        for cb in self._iter_checkboxes():
            cb.refresh()

    def _iter_checkboxes(self):
        # Checkboxes redraw lazily on their own <Button-1>; Select All/None
        # need an explicit repaint since they bypass that click.
        for child in self.root.winfo_children():
            yield from self._find_checkboxes(child)

    def _find_checkboxes(self, widget):
        if isinstance(widget, MDCheckbox):
            yield widget
        for child in widget.winfo_children():
            yield from self._find_checkboxes(child)

    # ---------- Run lifecycle ----------

    def _on_run(self):
        if self.running:
            return
        selected = [str(num) for num, var in self.module_vars.items() if var.get()]
        if not selected:
            md_alert(self.root, "No modules selected", "Select at least one module to run.")
            return

        dry_run = self.dry_run_var.get()
        names = [name for num, name, _ in MODULES if str(num) in selected]
        title = "Preview modules" if dry_run else "Apply changes"
        detail = ("Preview only — nothing changes unless you choose Run for Real below."
                   if dry_run else
                   "This will modify system packages/config and may prompt for your sudo password.")
        choice = md_confirm_run(self.root, title, detail, names, dry_run)
        if choice is None:
            return

        args = ["bash", ROYALUTIL_SH, f"--modules={','.join(selected)}"]
        if choice == "preview":
            args.append("--dry-run")

        env = os.environ.copy()
        self._apply_git_env(env)

        self._start_run(args, env)

    def _on_install_selected(self):
        if self.running:
            return
        selected_apps = [item_id for item_id, var in self.app_vars.items() if var.get()]
        selected_utils = [item_id for item_id, var in self.util_vars.items() if var.get()]
        if not selected_apps and not selected_utils:
            md_alert(self.root, "Nothing selected", "Check at least one app or utility to install.")
            return

        modules = []
        if selected_apps:
            modules.append("7")
        if selected_utils:
            modules.append("8")

        flatpak_items, util_items = load_catalog()
        app_names = {item_id: name for item_id, name, _ in flatpak_items}
        util_names = {item_id: name for item_id, name, _ in util_items}
        names = [app_names.get(i, i) for i in selected_apps] + \
                [util_names.get(i, i) for i in selected_utils]

        dry_run = self.dry_run_var.get()
        title = "Preview install" if dry_run else "Install selected"
        detail = ("Preview only — nothing changes unless you choose Run for Real below."
                   if dry_run else
                   "This will install the selected items and may prompt for your sudo password.")
        choice = md_confirm_run(self.root, title, detail, names, dry_run)
        if choice is None:
            return

        args = ["bash", ROYALUTIL_SH, f"--modules={','.join(modules)}"]
        if choice == "preview":
            args.append("--dry-run")

        env = os.environ.copy()
        if selected_apps:
            env["ROYALUTIL_APPS"] = ",".join(selected_apps)
        if selected_utils:
            env["ROYALUTIL_UTILITIES"] = ",".join(selected_utils)
        self._apply_git_env(env)

        self._start_run(args, env)

    def _apply_git_env(self, env):
        if self.git_name_var.get().strip():
            env["GIT_NAME"] = self.git_name_var.get().strip()
        if self.git_email_var.get().strip():
            env["GIT_EMAIL"] = self.git_email_var.get().strip()

    def _start_run(self, args, env):
        self.console.delete("1.0", "end")
        self.progress.set(0)
        self.status_label.config(text="Running...")
        self.run_btn.set_state("disabled")
        self.install_btn.set_state("disabled")
        self.cancel_btn.set_state("normal")
        self.input_entry.set_state("normal")
        self.send_btn.set_state("normal")
        self.running = True

        self._spawn(args, env)

    def _spawn(self, args, env):
        pid, master_fd = pty.fork()
        if pid == 0:
            os.chdir(SCRIPT_DIR)
            try:
                os.execvpe(args[0], args, env)
            except Exception:
                os._exit(1)
        else:
            self.child_pid = pid
            self.master_fd = master_fd
            self.reader_thread = threading.Thread(target=self._read_loop, daemon=True)
            self.reader_thread.start()

    def _read_loop(self):
        while True:
            try:
                data = os.read(self.master_fd, 4096)
            except OSError:
                break
            if not data:
                break
            text = data.decode("utf-8", errors="replace")
            self.event_queue.put(("output", text))
            if PASSWORD_RE.search(ANSI_RE.sub("", text)):
                self.event_queue.put(("password_prompt", None))
        try:
            _, status = os.waitpid(self.child_pid, 0)
        except ChildProcessError:
            status = 0
        self.event_queue.put(("done", status))

    def _poll_queue(self):
        try:
            while True:
                kind, payload = self.event_queue.get_nowait()
                if kind == "output":
                    self.terminal.feed(payload)
                    m = PROGRESS_RE.search(payload)
                    if m:
                        pct = int(m.group(1))
                        self.progress.set(pct)
                        self.status_label.config(text=f"{pct}% ({m.group(2)}/{m.group(3)})")
                elif kind == "password_prompt":
                    if not self.awaiting_password:
                        self.awaiting_password = True
                        self._ask_password()
                elif kind == "done":
                    self._on_done(payload)
        except queue.Empty:
            pass
        self.root.after(50, self._poll_queue)

    def _ask_password(self):
        pwd = md_prompt_password(self.root, "sudo password",
                                  "Royalutil needs administrator access to continue.")
        self.awaiting_password = False
        if pwd is None:
            pwd = ""
        try:
            os.write(self.master_fd, (pwd + "\n").encode())
        except OSError:
            pass

    def _send_input(self):
        if not self.running or self.master_fd is None:
            return
        text = self.input_var.get()
        self.input_var.set("")
        try:
            os.write(self.master_fd, (text + "\n").encode())
        except OSError:
            pass

    def _on_cancel(self):
        if not self.running or self.child_pid is None:
            return
        try:
            os.killpg(self.child_pid, signal.SIGTERM)
        except (OSError, ProcessLookupError):
            try:
                os.kill(self.child_pid, signal.SIGTERM)
            except (OSError, ProcessLookupError):
                pass
        self.status_label.config(text="Cancelling...")

    def _on_done(self, status):
        self.running = False
        self.run_btn.set_state("normal")
        self.install_btn.set_state("normal")
        self.cancel_btn.set_state("disabled")
        self.input_entry.set_state("disabled")
        self.send_btn.set_state("disabled")
        try:
            if self.master_fd is not None:
                os.close(self.master_fd)
        except OSError:
            pass
        self.master_fd = None
        self.child_pid = None

        ok = os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0
        if ok:
            self.status_label.config(text="Done")
            self.progress.set(100)
        else:
            self.status_label.config(text="Failed / interrupted")
        md_alert(self.root, "Royalutil",
                 "Finished successfully." if ok else
                 "Finished with errors or was cancelled.\nCheck the console output and log file for details.")

    def _open_log(self):
        if not os.path.isfile(LOG_FILE):
            md_alert(self.root, "Log", f"No log file yet at {LOG_FILE}")
            return
        try:
            os.system(f"xdg-open {LOG_FILE!r} >/dev/null 2>&1 &")
        except Exception:
            pass
        with open(LOG_FILE, "r", errors="replace") as f:
            content = f.read()

        win = tk.Toplevel(self.root)
        win.title("royalutil_setup.log")
        win.geometry("720x520")
        win.configure(bg=SURFACE)
        card = Card(win, fill=DARK_SURFACE, radius=20, pad=12)
        card.pack(fill="both", expand=True, padx=16, pady=16)
        text = scrolledtext.ScrolledText(
            card.inner, bg=DARK_SURFACE, fg=DARK_ON_SURFACE, relief="flat",
            font=("Monospace", 9), bd=0, highlightthickness=0,
        )
        text.pack(fill="both", expand=True)
        text.insert("1.0", content)
        text.see("end")
        text.config(state="disabled")


def main():
    if sys.platform != "linux":
        print("Royalutil GUI only supports Linux.", file=sys.stderr)
        sys.exit(1)
    root = tk.Tk()
    global FONT_FAMILY
    FONT_FAMILY = _resolve_font_family(root)
    RoyalutilGUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()
