import re

with open(r'C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_client_flutter\lib\main.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find "l'app" patterns
matches = re.findall(r'"[^"]*l\'app[^"]*"', content)
print('Found l\'app:', len(matches))

# Find "d'intervention" patterns
matches2 = re.findall(r'"[^"]*d\'intervention[^"]*"', content)
print('Found d\'intervention:', len(matches2))