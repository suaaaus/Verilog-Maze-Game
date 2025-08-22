def fill_image_from_binary_texts(binary_texts_64x128):
    image = [[0 for _ in range(128)] for _ in range(8)]
    for i in range(8):
        for j in range(128):
            byte_data = 0
            for k in range(8):
                index = i * 8 + k
                pixel_bit = int(binary_texts_64x128[index][j])
                byte_data |= (pixel_bit << k)
            image[i][j] = byte_data
    return image

# 1. 파일 읽기, 데이터 준비
INPUT_FILENAME = 'input_data.txt'
OUTPUT_FILENAME = 'output_hex_stream.txt' # 출력 파일 이름 변경
TARGET_WIDTH = 128
TARGET_HEIGHT = 64

binary_texts = []
try:
    with open(INPUT_FILENAME, 'r') as f:
        for line in f.readlines():
            line = line.strip()
            if line:
                binary_texts.append(line)
except FileNotFoundError:
    print(f"오류: '{INPUT_FILENAME}' 파일을 찾을 수 없습니다.")
    exit()

print(f"'{INPUT_FILENAME}' 파일을 성공적으로 읽었습니다.")
cropped_texts = [row[:TARGET_WIDTH] for row in binary_texts[:TARGET_HEIGHT]]

# 2. 변환 함수 호출
oled_image_data = fill_image_from_binary_texts(cropped_texts)

# 3. 수평 모드용으로 파일에 저장
with open(OUTPUT_FILENAME, 'w') as f:
    f.write(f"// Generated OLED Image Data for Horizontal Mode (1024 bytes)\n\n")
    
    for i in range(8):      # 페이지 0부터 7까지 순서대로
        for j in range(128):  # 각 페이지의 컬럼 0부터 127까지
            # 16진수 값만 쓰고 줄바꿈
            f.write(f"{oled_image_data[i][j]:02X}\n")

print(f"\n변환 완료.")

