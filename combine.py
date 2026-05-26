# combine.py
# Объединяет все файлы проекта LeoTrack в один текстовый файл

import os
from datetime import datetime

# === НАСТРОЙКИ ===
project_folder = r"C:\Users\tanis\Documents\leotrack_db"   # ← Измени, если папка другая

files = [
    ("docker-compose.yaml", "Docker Compose Configuration"),
    ("01_schema.sql", "1. Схема базы данных (DDL)"),
    ("02_data.sql", "2. Наполнение тестовыми данными"),
    ("03_functions.sql", "3. Пользовательские функции"),
    ("04_triggers.sql", "4. Триггеры и дополнительные таблицы"),
    ("05_queries.sql", "5. Аналитические SQL-запросы"),
    ("06_demo.sql", "6. Демонстрационный скрипт"),
]

def main():
    output_file = "LeoTrack_Full_Project_Combined.txt"
    output_path = os.path.join(project_folder, output_file)
    
    with open(output_path, "w", encoding="utf-8") as f:
        # Заголовок
        f.write("=" * 85 + "\n")
        f.write(" " * 20 + "LEO TRACK — ПОЛНЫЙ ПРОЕКТ БАЗЫ ДАННЫХ\n")
        f.write(" " * 25 + "Расчётно-графическая работа\n")
        f.write(f" " * 20 + f"Сгенерировано: {datetime.now().strftime('%d.%m.%Y %H:%M:%S')}\n")
        f.write("=" * 85 + "\n\n")
        
        for filename, title in files:
            filepath = os.path.join(project_folder, filename)
            
            if not os.path.exists(filepath):
                print(f"⚠️  Файл не найден: {filename}")
                continue
            
            # Разделитель
            f.write("\n" + "=" * 85 + "\n")
            f.write(f"📁 {title} — {filename}\n")
            f.write("=" * 85 + "\n\n")
            
            # Читаем и записываем содержимое
            with open(filepath, "r", encoding="utf-8") as infile:
                content = infile.read()
                f.write(content.rstrip() + "\n")
            
            print(f"✅ Добавлен: {filename}")
        
        f.write("\n" + "=" * 85 + "\n")
        f.write("                   КОНЕЦ ОБЪЕДИНЁННОГО ФАЙЛА\n")
        f.write("=" * 85 + "\n")
    
    print(f"\n🎉 Готово!")
    print(f"Файл создан: {output_path}")
    print("Можешь открыть его в Notepad++ или любом редакторе.")

if __name__ == "__main__":
    main()