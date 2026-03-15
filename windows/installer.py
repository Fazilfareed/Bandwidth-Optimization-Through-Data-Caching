import subprocess
import tkinter as tk
from tkinter import messagebox

def run_install():
    os_type = os_var.get()
    ip = ip_entry.get().strip()

    if not ip:
        messagebox.showerror("Error", "Please enter server IP")
        return

    try:
        if os_type == "linux":
            cmd = ["bash", "./pkg-cache.sh", "client", "install", ip]

        else:
            cmd = [
                "powershell",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                "pkg-cache-client.ps1",
                "-Action",
                "install",
                "-ServerHost",
                ip
            ]

        result = subprocess.run(cmd)

        if result.returncode == 0:
            messagebox.showinfo("Success", "Client installed successfully!")
        else:
            messagebox.showerror("Failed", "Something went wrong. Check server IP.")

    except Exception as e:
        messagebox.showerror("Error", str(e))


app = tk.Tk()
app.title("Pkg Cache Client Installer")
app.geometry("350x200")

tk.Label(app, text="Select Operating System").pack(pady=5)

os_var = tk.StringVar(value="linux")

tk.Radiobutton(app, text="Linux", variable=os_var, value="linux").pack()
tk.Radiobutton(app, text="Windows", variable=os_var, value="windows").pack()

tk.Label(app, text="Server IP Address").pack(pady=5)

ip_entry = tk.Entry(app)
ip_entry.pack()

tk.Button(app, text="Install", command=run_install).pack(pady=20)

app.mainloop()