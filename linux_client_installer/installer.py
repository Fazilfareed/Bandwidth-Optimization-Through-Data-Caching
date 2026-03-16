#!/usr/bin/env python3
import subprocess
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext, simpledialog
import os
import sys
import threading
import queue

# -----------------------------
# Detect base directory
# -----------------------------
if getattr(sys, 'frozen', False):
    BASE_DIR = sys._MEIPASS
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# -----------------------------
# Small helper: hover for ttk buttons
# -----------------------------
def add_hover(widget, style_name, hover_style_name):
    def on_enter(e):
        widget.configure(style=hover_style_name)
    def on_leave(e):
        widget.configure(style=style_name)
    widget.bind("<Enter>", on_enter)
    widget.bind("<Leave>", on_leave)

# -----------------------------
# Thread to run commands
# -----------------------------
class CommandThread(threading.Thread):
    def __init__(self, cmd, output_queue, password=None):
        super().__init__(daemon=True)
        self.cmd = cmd
        self.output_queue = output_queue
        self.password = password
        self.returncode = None

    def run(self):
        try:
            # Merge stderr into stdout so order is preserved
            process = subprocess.Popen(
                self.cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                stdin=subprocess.PIPE,
                text=True
            )

            # If we have a password (for sudo -S), send it immediately.
            # sudo will read from stdin when it prompts.
            if self.password is not None:
                try:
                    process.stdin.write(self.password + "\n")
                    process.stdin.flush()
                except Exception as e:
                    self.output_queue.put(f"[error sending password] {e}\n")

            # Stream output lines back to GUI
            for line in iter(process.stdout.readline, ""):
                if line:
                    self.output_queue.put(line)
            process.wait()
            self.returncode = process.returncode

        except Exception as e:
            self.output_queue.put(str(e) + "\n")
            self.returncode = -1

# -----------------------------
# Main Application
# -----------------------------
class InstallerApp(tk.Tk):

    def __init__(self):
        super().__init__()

        self.title("Pkg Cache Client Installer (Linux)")
        self.geometry("640x420")

        self.output_queue = queue.Queue()
        self.thread = None

        self.frame_menu = ttk.Frame(self, padding=12)
        self.frame_ip = ttk.Frame(self, padding=12)
        self.frame_result = ttk.Frame(self, padding=12)

        self.create_menu_frame()
        self.create_ip_frame()
        self.create_result_frame()

        self.frame_menu.pack(fill="both", expand=True)

        self.after(150, self.poll_output)

    # -------------------------
    # Screen switching
    # -------------------------
    def show_frame(self, frame):
        for f in [self.frame_menu, self.frame_ip, self.frame_result]:
            f.pack_forget()
        frame.pack(fill="both", expand=True)

    # -------------------------
    # Main Menu
    # -------------------------
    def create_menu_frame(self):
        ttk.Label(
            self.frame_menu,
            text="Select Action",
            font=("Segoe UI", 16, "bold")
        ).pack(pady=15)

        btn_frame = ttk.Frame(self.frame_menu)
        btn_frame.pack(pady=10)

        b1 = ttk.Button(
            btn_frame,
            text="Install",
            style="Accent.TButton",
            width=22,
            command=lambda: self.go_ip("install")
        )
        b1.grid(row=0, column=0, pady=10)

        b2 = ttk.Button(
            btn_frame,
            text="Reset",
            style="Neutral.TButton",
            width=22,
            command=lambda: self.go_ip("reset")
        )
        b2.grid(row=1, column=0, pady=10)

        b3 = ttk.Button(
            btn_frame,
            text="Status",
            style="Neutral.TButton",
            width=22,
            command=lambda: self.go_ip("status")
        )
        b3.grid(row=2, column=0, pady=10)

        b4 = ttk.Button(
            btn_frame,
            text="Ping Server",
            style="Neutral.TButton",
            width=22,
            command=lambda: self.go_ip("ping")
        )
        b4.grid(row=3, column=0, pady=10)

    # -------------------------
    # IP Screen
    # -------------------------
    def create_ip_frame(self):
        ttk.Label(self.frame_ip,
                  text="Enter Server IP (if required)",
                  font=("TkDefaultFont", 12, "bold")).pack(anchor="w")

        self.ip_entry = ttk.Entry(self.frame_ip, width=35)
        self.ip_entry.pack(pady=10)

        btns = ttk.Frame(self.frame_ip)
        btns.pack()

        ttk.Button(btns, text="Back",
                   command=lambda: self.show_frame(self.frame_menu)).pack(side="left", padx=10)

        ttk.Button(btns, text="Run",
                   command=self.run_with_ip).pack(side="right", padx=10)

    def go_ip(self, action):
        self.current_action = action
        self.ip_entry.delete(0, tk.END)
        self.show_frame(self.frame_ip)

    def run_with_ip(self):
        ip = self.ip_entry.get().strip()
        # For install, ip is required
        if self.current_action == "install" and not ip:
            messagebox.showerror("Error", "Please enter server IP for install")
            return
        # For ping also require ip
        if self.current_action == "ping" and not ip:
            messagebox.showerror("Error", "Please enter server IP to ping")
            return
        self.run_action(self.current_action, ip if ip else None)

    # -------------------------
    # Result Screen
    # -------------------------
    def create_result_frame(self):
        ttk.Label(self.frame_result,
                  text="Execution Output",
                  font=("TkDefaultFont", 12, "bold")).pack(anchor="w")

        self.progress = ttk.Progressbar(self.frame_result, mode="indeterminate")
        self.progress.pack(fill="x", pady=6)

        self.log = scrolledtext.ScrolledText(self.frame_result, height=16)
        self.log.pack(fill="both", expand=True)

        ttk.Button(self.frame_result,
                   text="Back to Menu",
                   command=lambda: self.show_frame(self.frame_menu)).pack(pady=8)

    # -------------------------
    # Run commands
    # -------------------------
    def run_action(self, action, ip=None):
        try:
            script = os.path.join(BASE_DIR, "pkg-cache.sh")

            password = None
            use_sudo = False
            cmd = None

            if action == "install":
                # install requires server IP
                if not ip:
                    messagebox.showerror("Error", "Install needs server IP")
                    return
                use_sudo = True
                cmd = ["sudo", "-S", "bash", script, "client", "install", ip]

            elif action == "reset":
                use_sudo = True
                cmd = ["sudo", "-S", "bash", script, "client", "reset"]

            elif action == "status":
                # status may or may not require sudo depending on your script;
                # default to using sudo so it works for cases that require privileges.
                use_sudo = True
                cmd = ["sudo", "-S", "bash", script, "client", "status"]
                if ip:
                    # if script accepts server host as extra arg, append it
                    cmd.append(ip)

            elif action == "ping":
                if not ip:
                    messagebox.showerror("Error", "Ping needs server IP")
                    return
                # use linux ping
                cmd = ["ping", "-c", "4", ip]

            else:
                messagebox.showerror("Error", f"Unknown action: {action}")
                return

            # If this action uses sudo, prompt for password
            if use_sudo:
                password = simpledialog.askstring(
                    "Sudo Password",
                    "Enter your sudo password (required for administrator actions):",
                    show="*",
                    parent=self
                )
                if password is None:
                    # user cancelled password prompt
                    messagebox.showinfo("Cancelled", "Operation cancelled by user")
                    return

            # Switch to result screen and start thread
            self.show_frame(self.frame_result)
            self.log.delete("1.0", tk.END)
            self.progress.start(10)

            self.thread = CommandThread(cmd, self.output_queue, password=password)
            self.thread.start()

        except Exception as e:
            messagebox.showerror("Error", str(e))

    # -------------------------
    # Poll output
    # -------------------------
    def poll_output(self):
        while not self.output_queue.empty():
            line = self.output_queue.get()
            self.log.insert(tk.END, line)
            self.log.see(tk.END)

        if self.thread and not self.thread.is_alive():
            self.progress.stop()
            if self.thread.returncode == 0:
                messagebox.showinfo("Success", "Operation completed successfully")
            else:
                messagebox.showerror("Error", f"Operation failed (exit code {self.thread.returncode})")
            self.thread = None

        self.after(150, self.poll_output)

if __name__ == "__main__":
    app = InstallerApp()
    app.mainloop()
