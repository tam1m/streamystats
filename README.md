# Streamystats

Streamystats is a statistics service for Jellyfin, providing analytics and data visualization. 📈

## ✨ Features

- 🖥️ Dashboard with overview statistics
- 👤 User-specific watch history and statistics
- 🌟 Most popular item tracking
- ⏱️ Watch time graphs
- 🔄 Full and partial sync options with Jellyfin server
- 🏠 Multi-server and user support

## Roadmap

- [ ] Individual item statistics
- [ ] More statistics about unwatched items and maybe the possibility to remove old or unwatched items
- [ ] More granular sync options
- [ ] Personal statistics only visible to that user

## 🚀 Getting started

1. Install the Playback Reporting Plugin on your Jellyfin server
2. Install Docker and Docker Compose if you haven't already.
3. Copy the `docker-compose.yml` file to your desired location. Change any ports if needed. Default web port is 3000.
4. Start the application with `docker-compose up -d`
5. Open your browser and navigate to `http://localhost:3000`
6. Follow the setup wizard to connect your Jellyfin server.

## 📸 Screenshots
<img width="1545" alt="Screenshot 2024-11-03 at 10 56 53" src="https://github.com/user-attachments/assets/4abec082-95e4-4cd6-b1fe-e0dd43213e6e">
<img width="1545" alt="Screenshot 2024-11-03 at 11 11 55" src="https://github.com/user-attachments/assets/34488f6c-8c2d-4888-a38f-6e314b0f253c">

<img width="1545" alt="Screenshot 2024-11-03 at 10 57 04" src="https://github.com/user-attachments/assets/3dbbc7b0-2f64-44de-9b0c-a524de1a660d">
<img width="1545" alt="Screenshot 2024-11-03 at 10 57 35" src="https://github.com/user-attachments/assets/9dac59d8-54eb-4474-bc21-caf782492c14">

<img width="356" alt="Screenshot 2024-11-03 at 10 57 43" src="https://github.com/user-attachments/assets/b5988b08-8ba6-4fca-99d2-8e221016fcc9">
<img width="357" alt="Screenshot 2024-11-03 at 10 57 46" src="https://github.com/user-attachments/assets/34db1a56-dc05-4c87-b0c7-290e23be6d8c">

## 🛠️ Tech Stack

- Frontend: Next.js, React, TypeScript
- Backend: Phoenix (Elixir)
- Database: PostgreSQL
- Containerization: Docker
