# Streamystats

Streamystats is a statistics service for Jellyfin, providing analytics and data visualization. 📈

## ✨ Features

- 🖥️ Dashboard with overview statistics
- 👤 User-specific watch history and statistics
- 🌟 Most popular item tracking
- ⏱️ Watch time graphs
- 🔄 Full and partial sync options with Jellyfin server

## 🚀 Getting started

1. Install the Playback Reporting Plugin on your Jellyfin server
2. Clone this repository to your server
3. Install Docker and Docker Compose if you haven't already.
4. Change the `SECRET_KEY_BASE` in the `docker-compose.yml` file if you plan to use the application in production.
5. Start the application with `docker-compose up -d`
6. Open your browser and navigate to `http://localhost:3000`
7. Follow the setup wizard to connect your Jellyfin server.

## 📸 Screenshots

<img width="1420" alt="Screenshot 2024-10-29 at 23 08 14" src="https://github.com/user-attachments/assets/ec942b14-4935-4024-950b-bd2a3dd8c331">
<img width="1420" alt="Screenshot 2024-10-29 at 23 08 20" src="https://github.com/user-attachments/assets/bd0a71f5-8ee6-481a-b51f-a430458cba1c">
<img width="1420" alt="Screenshot 2024-10-29 at 23 08 27" src="https://github.com/user-attachments/assets/18d7364d-5feb-4589-b65d-1c4ce7e7b8f8">
<img width="1420" alt="Screenshot 2024-10-29 at 23 08 32" src="https://github.com/user-attachments/assets/7fb03f9a-54c7-4abb-8ced-97b022f03a4c">
<img width="1420" alt="Screenshot 2024-10-29 at 23 08 36" src="https://github.com/user-attachments/assets/4292f8de-54b5-4486-8171-fe78ece71616">

## 🛠️ Tech Stack

- Frontend: Next.js, React, TypeScript
- Backend: Phoenix (Elixir)
- Database: PostgreSQL
- Containerization: Docker
