import subprocess
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext
import os
import sys
import threading
import queue

# -----------------------------
# Detect base directory
# -----------------------------
if getattr(sys, 'frozen', False):
    BASE_DIR = os.path.dirname(sys.executable)
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# -----------------------------
# Thread to run commands
# -----------------------------
class CommandThread(threading.Thread):

    def __init__(self, cmd, output_queue):
        super().__init__(daemon=True)
        self.cmd = cmd
        self.output_queue = output_queue
        self.returncode = None

    def run(self):

        try:
            process = subprocess.Popen(
                self.cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )

            for line in process.stdout:
                self.output_queue.put(line)

            for line in process.stderr:
                self.output_queue.put(line)

            process.wait()
            self.returncode = process.returncode

        except Exception as e:
            self.output_queue.put(str(e))
            self.returncode = -1


# -----------------------------
# Main Application
# -----------------------------
class InstallerApp(tk.Tk):

    def __init__(self):
        super().__init__()

        self.title("Pkg Cache Client Installer")
        self.geometry("640x420")

        self.selected_os = tk.StringVar(value="windows")
        self.output_queue = queue.Queue()
        self.thread = None

        self.frame_os = ttk.Frame(self, padding=12)
        self.frame_menu = ttk.Frame(self, padding=12)
        self.frame_ip = ttk.Frame(self, padding=12)
        self.frame_result = ttk.Frame(self, padding=12)

        self.create_os_frame()
        self.create_menu_frame()
        self.create_ip_frame()
        self.create_result_frame()

        self.frame_os.pack(fill="both", expand=True)

        self.after(150, self.poll_output)

    # -------------------------
    # Screen switching
    # -------------------------
    def show_frame(self, frame):

        for f in [self.frame_os, self.frame_menu, self.frame_ip, self.frame_result]:
            f.pack_forget()

        frame.pack(fill="both", expand=True)

    # -------------------------
    # OS Selection
    # -------------------------
    def create_os_frame(self):

        ttk.Label(self.frame_os,
                  text="Step 1 — Select Operating System",
                  font=("TkDefaultFont", 12, "bold")).pack(anchor="w")

        rb = ttk.Frame(self.frame_os)
        rb.pack(pady=10)

        ttk.Radiobutton(rb, text="Windows", variable=self.selected_os, value="windows").pack(side="left", padx=10)
        ttk.Radiobutton(rb, text="Linux", variable=self.selected_os, value="linux").pack(side="left", padx=10)

        ttk.Button(self.frame_os, text="Next",
                   command=lambda: self.show_frame(self.frame_menu)).pack(anchor="e", pady=10)

    # -------------------------
    # Main Menu
    # -------------------------
    def create_menu_frame(self):

        ttk.Label(self.frame_menu,
                  text="Select Action",
                  font=("TkDefaultFont", 12, "bold")).pack(anchor="w")

        ttk.Button(self.frame_menu, text="Install",
                   command=lambda: self.go_ip("install")).pack(pady=6)

        ttk.Button(self.frame_menu, text="Reset",
                   command=lambda: self.run_action("reset")).pack(pady=6)

        ttk.Button(self.frame_menu, text="Status",
                   command=lambda: self.go_ip("status")).pack(pady=6)

        ttk.Button(self.frame_menu, text="Ping Server",
                   command=lambda: self.go_ip("ping")).pack(pady=6)

        ttk.Button(self.frame_menu, text="Change OS",
                   command=lambda: self.show_frame(self.frame_os)).pack(pady=10)

    # -------------------------
    # IP Screen
    # -------------------------
    def create_ip_frame(self):

        ttk.Label(self.frame_ip,
                  text="Enter Server IP",
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

        if not ip:
            messagebox.showerror("Error", "Please enter server IP")
            return

        self.run_action(self.current_action, ip)

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
    # Run commands (LOGIC UNCHANGED)
    # -------------------------
    def run_action(self, action, ip=None):

        os_type = self.selected_os.get()

        try:

            if action == "install":

                if os_type == "windows":

                    script = os.path.join(BASE_DIR, "pkg-cache-client.ps1")

                    cmd = [
                        "powershell",
                        "-ExecutionPolicy",
                        "Bypass",
                        "-File",
                        script,
                        "-Action",
                        "install",
                        "-ServerHost",
                        ip
                    ]

                else:

                    script = os.path.join(BASE_DIR, "pkg-cache.sh")
                    cmd = ["bash", script, "client", "install", ip]

            elif action == "reset":

                if os_type == "windows":

                    script = os.path.join(BASE_DIR, "pkg-cache-client.ps1")

                    cmd = [
                        "powershell",
                        "-ExecutionPolicy",
                        "Bypass",
                        "-File",
                        script,
                        "-Action",
                        "reset"
                    ]

                else:

                    script = os.path.join(BASE_DIR, "pkg-cache.sh")
                    cmd = ["bash", script, "client", "reset"]

            elif action == "status":

                if os_type == "windows":

                    script = os.path.join(BASE_DIR, "pkg-cache-client.ps1")

                    cmd = [
                        "powershell",
                        "-ExecutionPolicy",
                        "Bypass",
                        "-File",
                        script,
                        "-Action",
                        "status",
                        "-ServerHost",
                        ip
                    ]

                else:

                    script = os.path.join(BASE_DIR, "pkg-cache.sh")
                    cmd = ["bash", script, "client", "status"]

            elif action == "ping":

                if os.name == "nt":
                    cmd = ["ping", "-n", "4", ip]
                else:
                    cmd = ["ping", "-c", "4", ip]

            # Start result UI
            self.show_frame(self.frame_result)
            self.log.delete("1.0", tk.END)
            self.progress.start(10)

            self.thread = CommandThread(cmd, self.output_queue)
            self.thread.start()

        except Exception as e:
            messagebox.showerror("Error", str(e))

    # -------------------------
    # Poll command output
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
                messagebox.showerror("Error", "Operation failed")

            self.thread = None

        self.after(150, self.poll_output)


# -----------------------------
# Run app
# -----------------------------
app = InstallerApp()
app.mainloop()