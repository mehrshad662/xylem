import tkinter as tk

root = tk.Tk()
root.title("Byggstatus")

def update_status():
    button.config(text="✔ Pipeline klar!", bg="green", fg="white")  # Uppdatera texten och färgerna på knappen
    root.after(5000, root.destroy)  # Stänger fönstret efter 5 sekunder

button = tk.Button(root, text="Kör pipeline", command=update_status, font=("Arial", 14), bg="blue", fg="white")
button.pack(pady=20, padx=50)

root.after(10000, root.destroy)  # Stänger fönstret efter 10 sekunder om inget klickas
root.mainloop()

