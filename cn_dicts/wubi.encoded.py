#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
五笔词库生成工具
支持多种编码规则，可交互式输入或批量处理文件
"""

import os
import sys
import subprocess
import re
import datetime
import importlib
from typing import Dict, Set, Tuple, Optional, List, Any

# 文件常量定义
SINGLE_CHAR_FILE = "86word-8105-better.txt"
PHRASE_WEIGHT_FILE = "phrase_weight.txt"
OUTPUT_FILE = "wubi.user.dict.yaml"
FAIL_FILE = "fail.txt"

class Config:
    """配置参数"""
    # 记录文件保存目录（跨平台兼容）
    RECORD_DIR = os.path.join(
        os.path.expanduser("~"),
        "OneDrive",
        "Backup",
        "RimeSync",
        "update_record"
    )
    
    # 默认权重值
    DEFAULT_WEIGHT = "100"
    
    # 需要检查的Python包
    REQUIRED_PACKAGES = ["pypinyin"]

def install_package(package_name):
    """
    安装指定的Python包
    """
    try:
        print(f"正在安装 {package_name}...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", package_name])
        print(f"✓ {package_name} 安装成功")
        return True
    except subprocess.CalledProcessError as e:
        print(f"✗ {package_name} 安装失败: {e}")
        return False
    except Exception as e:
        print(f"✗ {package_name} 安装失败: {e}")
        return False

def check_and_install_packages():
    """
    检查并自动安装缺失的Python包
    """
    print("检查Python包依赖...")
    missing_packages = []
    
    for package in Config.REQUIRED_PACKAGES:
        try:
            importlib.import_module(package.replace("-", "_"))
            print(f"✓ {package} 已安装")
        except ImportError:
            print(f"✗ {package} 未安装")
            missing_packages.append(package)
    
    if missing_packages:
        print(f"\n发现 {len(missing_packages)} 个缺失的包:")
        for package in missing_packages:
            print(f"  - {package}")
        
        response = input("\n是否自动安装缺失的包？(y/n): ").strip().lower()
        if response in ['y', 'yes', '是', '1']:
            for package in missing_packages:
                if not install_package(package):
                    print(f"警告: {package} 安装失败，相关功能可能不可用")
        else:
            print("请手动安装缺失的包:")
            for package in missing_packages:
                print(f"  pip install {package}")
            input("按Enter键继续...")
    else:
        print("所有依赖包已安装 ✓")
    
    print("-" * 30)

def get_pinyin_initials(text):
    """
    获取中文字符的拼音首字母
    
    Args:
        text: 包含中文字符的文本
        
    Returns:
        拼音首字母字符串（小写），非中文字符忽略
    """
    try:
        # 动态导入pypinyin，避免没有安装时直接报错
        from pypinyin import lazy_pinyin, Style
        
        # 只提取中文字符
        chinese_chars = extract_chinese_chars(text)
        if not chinese_chars:
            return ""
        
        # 获取拼音首字母
        pinyin_initials = lazy_pinyin(chinese_chars, style=Style.FIRST_LETTER)
        # 合并为字符串并转换为小写
        initials = ''.join(pinyin_initials).lower()
        return initials
    except ImportError:
        print("警告: pypinyin模块未安装，无法获取拼音首字母")
        return ""
    except Exception as e:
        print(f"获取拼音首字母时出错: {e}")
        return ""

def validate_wubi_code(code: str) -> bool:
    """
    验证五笔编码格式
    允许全小写字母，可以有空格
    """
    if not code:
        return False
    # 允许小写字母和空格
    if not re.match(r'^[a-z ]+$', code):
        return False
    return True

def is_valid_phrase(phrase: str) -> bool:
    """
    验证词组是否有效
    允许汉字、字母、数字、符号及其组合
    """
    if not phrase or not phrase.strip():
        return False
    return True

def read_single_char_codes(filename: str = SINGLE_CHAR_FILE) -> Dict[str, str]:
    """
    读取单字编码表，返回字典：{汉字: 编码}
    
    Args:
        filename: 编码表文件路径
        
    Returns:
        单字编码字典
    """
    char_codes = {}
    if not os.path.exists(filename):
        print(f"错误: 文件 {filename} 不存在！")
        return char_codes

    try:
        with open(filename, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                parts = line.split('\t')
                if len(parts) >= 2:
                    char = parts[0]
                    code = parts[1].lower()  # 确保编码为小写
                    char_codes[char] = code
        print(f"已读取 {len(char_codes)} 个单字编码")
        return char_codes
    except Exception as e:
        print(f"读取文件 {filename} 时出错: {e}")
        return char_codes

def read_phrase_weights(filename: str = PHRASE_WEIGHT_FILE) -> Dict[str, str]:
    """
    读取词语权重表，返回字典：{词语: 权重(字符串)}
    如果词组出现多次，保留最大权重值
    
    Args:
        filename: 权重表文件路径
        
    Returns:
        词语权重字典
    """
    phrase_weights = {}
    if not os.path.exists(filename):
        print(f"警告: 文件 {filename} 不存在！将使用默认权重")
        return phrase_weights

    try:
        with open(filename, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                parts = line.split('\t')
                if len(parts) >= 2:
                    phrase = parts[0]
                    weight_str = parts[1].strip()

                    # 验证权重是否为纯数字
                    if not re.match(r'^\d+$', weight_str):
                        print(f"警告: 权重值 '{weight_str}' 不是有效数字，将按0处理")
                        weight_int = 0
                    else:
                        weight_int = int(weight_str)

                    # 如果词组已存在，比较并保留最大值
                    if phrase in phrase_weights:
                        try:
                            existing_weight = int(phrase_weights[phrase])
                            if weight_int > existing_weight:
                                phrase_weights[phrase] = weight_str
                        except ValueError:
                            # 如果现有权重无法转换，使用新的
                            phrase_weights[phrase] = weight_str
                    else:
                        phrase_weights[phrase] = weight_str

        print(f"已读取 {len(phrase_weights)} 个词语权重（已去重，保留最大权重）")
        return phrase_weights
    except Exception as e:
        print(f"读取文件 {filename} 时出错: {e}")
        return phrase_weights

def get_first_code(char: str, char_codes: Dict[str, str]) -> str:
    """获取汉字的第一码，返回小写字母"""
    code = char_codes.get(char, "")
    return code[0:1] if code else "x"

def get_first_two_codes(char: str, char_codes: Dict[str, str]) -> str:
    """获取汉字的前两码，返回小写字母"""
    code = char_codes.get(char, "")
    if len(code) >= 2:
        return code[:2].lower()
    elif len(code) == 1:
        return code.lower() + "x"
    else:
        return "xx"

def rule_standard_wubi(phrase: str, char_codes: Dict[str, str]) -> str:
    """
    规则一：标准五笔编码规则（最多4码）
    """
    length = len(phrase)

    if length == 1:
        return char_codes.get(phrase, "xxxx").lower()
    elif length == 2:
        code1 = get_first_two_codes(phrase[0], char_codes)
        code2 = get_first_two_codes(phrase[1], char_codes)
        return (code1 + code2)[:4].lower()
    elif length == 3:
        code1 = get_first_code(phrase[0], char_codes)
        code2 = get_first_code(phrase[1], char_codes)
        code3 = get_first_two_codes(phrase[2], char_codes)
        return (code1 + code2 + code3)[:4].lower()
    elif length == 4:
        codes = [get_first_code(char, char_codes) for char in phrase]
        return "".join(codes)[:4].lower()
    else:
        code1 = get_first_code(phrase[0], char_codes)
        code2 = get_first_code(phrase[1], char_codes)
        code3 = get_first_code(phrase[2], char_codes)
        code_last = get_first_code(phrase[-1], char_codes)
        return (code1 + code2 + code3 + code_last)[:4].lower()

def rule_one_code_per_char(phrase: str, char_codes: Dict[str, str]) -> str:
    """
    规则二：一字一码编码规则
    """
    length = len(phrase)

    if length == 1:
        return char_codes.get(phrase, "xxxx").lower()
    elif length == 2:
        code1 = get_first_two_codes(phrase[0], char_codes)
        code2 = get_first_two_codes(phrase[1], char_codes)
        return (code1 + code2)[:4].lower()
    elif length == 3:
        code1 = get_first_code(phrase[0], char_codes)
        code2 = get_first_code(phrase[1], char_codes)
        code3 = get_first_two_codes(phrase[2], char_codes)
        return (code1 + code2 + code3)[:4].lower()
    else:
        codes = [get_first_code(char, char_codes) for char in phrase]
        return "".join(codes)[:4].lower()

def rule_first_two_chars_two_codes_rest_one(phrase: str, char_codes: Dict[str, str]) -> str:
    """
    规则三：前两字每字前两码后字一码编码规则
    """
    length = len(phrase)

    if length == 1:
        return char_codes.get(phrase, "xxxx").lower()
    elif length == 2:
        code1 = get_first_two_codes(phrase[0], char_codes)
        code2 = get_first_two_codes(phrase[1], char_codes)
        return (code1 + code2)[:4].lower()
    else:
        code_parts = []
        
        if length >= 1:
            code_parts.append(get_first_two_codes(phrase[0], char_codes))
        if length >= 2:
            code_parts.append(get_first_two_codes(phrase[1], char_codes))
            
        for i in range(2, length):
            code_parts.append(get_first_code(phrase[i], char_codes))
            
        full_code = "".join(code_parts)
        return full_code[:4].lower()

def rule_all_two_codes(phrase: str, char_codes: Dict[str, str]) -> str:
    """
    规则四：每个字都取前两码编码规则
    """
    codes = []
    total_length = 0

    for char in phrase:
        if total_length >= 4:
            break

        two_codes = get_first_two_codes(char, char_codes)
        remaining = 4 - total_length
        if len(two_codes) <= remaining:
            codes.append(two_codes)
            total_length += len(two_codes)
        else:
            codes.append(two_codes[:remaining])
            total_length += remaining

    result = "".join(codes)
    if len(result) < 4:
        result = result + "x" * (4 - len(result))

    return result[:4].lower()

def rule_free_coding(phrase: str, char_codes: Dict[str, str]) -> str:
    """
    规则五：自由编码规则
    用户手动输入自定义编码
    """
    # 对于规则五，编码将由用户输入，这里返回空字符串
    return ""

def rule_wubi_pinyin_initials(phrase: str, char_codes: Dict[str, str]) -> str:
    """
    规则六：五笔编码 + 拼音首字母
    - 先使用规则一生成五笔编码（4码）
    - 然后获取词组的拼音首字母，附加在五笔编码后面
    - 最终编码 = 五笔编码 + 拼音首字母
    """
    # 首先使用规则一生成五笔编码
    wubi_code = rule_standard_wubi(phrase, char_codes)
    
    # 获取拼音首字母
    pinyin_initials = get_pinyin_initials(phrase)
    
    # 组合编码
    if pinyin_initials:
        return wubi_code + pinyin_initials
    else:
        return wubi_code

def generate_wubi_code(phrase: str, char_codes: Dict[str, str], rule: int = 1) -> str:
    """
    根据指定规则为词语生成编码
    
    Args:
        phrase: 待编码的词语
        char_codes: 单字编码字典
        rule: 编码规则，1-6分别对应六种规则
        
    Returns:
        生成的编码字符串（小写）
    """
    if rule == 1:
        code = rule_standard_wubi(phrase, char_codes)
    elif rule == 2:
        code = rule_one_code_per_char(phrase, char_codes)
    elif rule == 3:
        code = rule_first_two_chars_two_codes_rest_one(phrase, char_codes)
    elif rule == 4:
        code = rule_all_two_codes(phrase, char_codes)
    elif rule == 5:
        code = rule_free_coding(phrase, char_codes)
    elif rule == 6:
        code = rule_wubi_pinyin_initials(phrase, char_codes)
    else:
        code = rule_standard_wubi(phrase, char_codes)
    
    return code.lower()

def read_existing_entries(filename: str = OUTPUT_FILE) -> Set[str]:
    """
    读取已存在的词库条目，返回已存在的词语集合
    """
    existing_phrases = set()
    if os.path.exists(filename):
        try:
            with open(filename, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if line:
                        parts = line.split('\t')
                        if parts:
                            phrase = parts[0]
                            existing_phrases.add(phrase)
        except Exception as e:
            print(f"读取已有词库 {filename} 时出错: {e}")
    return existing_phrases

def clean_output_file(filename: str) -> None:
    """
    清理输出文件，确保没有空行
    """
    if os.path.exists(filename):
        try:
            with open(filename, 'r', encoding='utf-8') as f:
                lines = [line.rstrip('\n') for line in f if line.strip()]

            with open(filename, 'w', encoding='utf-8') as f:
                for line in lines:
                    f.write(line + '\n')
        except Exception as e:
            print(f"清理输出文件 {filename} 时出错: {e}")

def open_file_with_default_app(filename: str) -> None:
    """
    使用默认程序打开文件
    """
    try:
        if os.path.exists(filename):
            if sys.platform == 'win32':
                os.startfile(filename)
            elif sys.platform == 'darwin':
                subprocess.run(['open', filename])
            else:
                subprocess.run(['xdg-open', filename])
            print(f"已打开文件: {filename}")
        else:
            print(f"文件不存在: {filename}")
    except Exception as e:
        print(f"无法打开文件 {filename}: {e}")

def select_encoding_rule() -> int:
    """
    显示菜单让用户选择编码规则
    """
    print("=" * 50)
    print("请选择编码规则：")
    print("1. 标准五笔编码规则（最多4码）")
    print("   两个汉字：各取前两码（共4码）")
    print("   三个汉字：取前两个第一码和第三个前两码（共4码）")
    print("   四个汉字：各取第一码（共4码）")
    print("   五个及以上汉字：取前三个第一码和最后一个第一码（共4码）")
    print()
    print("2. 一字一码编码规则：")
    print("   两个汉字：各取前两码")
    print("   三个汉字：取前两个第一码和第三个前两码")
    print("   四个及以上汉字：每个汉字取第一码")
    print()
    print("3. 前两字每字前两码后字一码编码规则：")
    print("   两个汉字：各取前两码（共4码）")
    print("   三个汉字：前两个各取前两码，第三个取第一码（最多取4码）")
    print("   四个汉字：前两个各取前两码，后面两个各取第一码（最多取4码）")
    print("   五个及以上汉字：前两个各取前两码，后面每个取第一码（最多取4码）")
    print()
    print("4. 每个字都取前两码编码规则：")
    print("   每个汉字都取前两码，然后拼接，直到达到4码")
    print()
    print("5. 自由编码规则：")
    print("   用户为每个词组输入自定义编码")
    print("   编码可以是任意长度的字母和空格（全小写）")
    print("   支持词组包含汉字、字母、数字、标点等任意字符")
    print()
    print("6. 五笔编码 + 拼音首字母：")
    print("   先使用规则一生成五笔编码（4码）")
    print("   然后获取词组的拼音首字母，附加在五笔编码后面")
    print("   最终编码 = 五笔编码 + 拼音首字母")
    print("=" * 50)

    while True:
        try:
            choice = input("请输入选择的规则编号 (1-6): ").strip()
            if choice in ['1', '2', '3', '4', '5', '6']:
                rule = int(choice)
                print(f"已选择规则 {rule}")
                return rule
            else:
                print("输入错误，请输入1-6之间的数字")
        except KeyboardInterrupt:
            print("\n用户取消操作")
            sys.exit(0)
        except Exception as e:
            print(f"输入错误: {e}")

def extract_chinese_chars(text: str) -> str:
    """
    从文本中提取中文字符（忽略标点符号和其他字符）
    """
    chinese_chars = re.findall(r'[\u4e00-\u9fff]', text)
    return ''.join(chinese_chars)

def check_all_chars_exist(phrase: str, char_codes: Dict[str, str]) -> bool:
    """
    检查词组中的所有中文字符是否都存在于单字编码表中
    忽略非中文字符
    """
    chinese_chars = extract_chinese_chars(phrase)

    if not chinese_chars:
        return False

    for char in chinese_chars:
        if char not in char_codes:
            return False

    return True

def is_file_path(input_str: str) -> bool:
    """
    判断输入是否为文件路径
    """
    cleaned_input = input_str.strip()
    if cleaned_input.startswith('"') and cleaned_input.endswith('"'):
        cleaned_input = cleaned_input[1:-1]
    elif cleaned_input.startswith("'") and cleaned_input.endswith("'"):
        cleaned_input = cleaned_input[1:-1]

    return os.path.exists(cleaned_input)

def interactive_single_input(phrase: str, rule: int, char_codes: Dict[str, str], 
                            phrase_weights: Dict[str, str], existing_phrases: Set[str]) -> Tuple[bool, str]:
    """
    交互式单条输入模式：处理单个词组
    """
    output_filename = OUTPUT_FILE
    added = False

    # 检查词组是否已存在
    if phrase in existing_phrases:
        print(f"  词组 '{phrase}' 已存在于词库中，跳过")
        return False, "已存在"

    # 对于规则五和规则六，不需要检查汉字是否在编码表中
    if rule not in [5, 6]:
        # 检查词组中的所有汉字是否都存在于编码表中
        if not check_all_chars_exist(phrase, char_codes):
            print(f"  警告: 词组 '{phrase}' 中包含未编码的汉字")
            return False, "包含未编码汉字"

    # 对于规则五（自由编码），直接使用用户输入的词组
    if rule == 5:
        # 规则五：自由编码，需要用户输入
        while True:
            try:
                user_code = input(f"  请为词组 '{phrase}' 输入自定义编码: ").strip()
                if not user_code:
                    print("  错误: 编码不能为空，请重新输入")
                    continue
                
                # 转换为小写
                user_code = user_code.lower()
                
                # 验证编码格式：只能是字母和空格
                if not re.match(r'^[a-z ]+$', user_code):
                    print("  错误: 编码只能包含小写字母和空格，请重新输入")
                    continue
                    
                # 去除多余的空格
                code = ' '.join(user_code.split())
                break
            except KeyboardInterrupt:
                print("\n  用户取消输入")
                return False, "用户取消"
            except Exception as e:
                print(f"  输入错误: {e}")
                return False, str(e)
    else:
        # 规则六需要提取中文字符用于编码和拼音
        if rule == 6:
            chinese_chars = extract_chinese_chars(phrase)
            if not chinese_chars:
                print(f"  警告: 词组 '{phrase}' 中不包含中文字符")
                return False, "不包含中文字符"
            
            # 生成编码（规则六会同时使用中文字符进行编码和拼音处理）
            code = generate_wubi_code(chinese_chars, char_codes, rule)
        else:
            # 其他规则：需要提取中文字符用于编码
            chinese_chars = extract_chinese_chars(phrase)
            if not chinese_chars:
                print(f"  警告: 词组 '{phrase}' 中不包含中文字符")
                return False, "不包含中文字符"

            # 生成编码（只使用中文字符）
            code = generate_wubi_code(chinese_chars, char_codes, rule)

    # 获取权重（使用最大权重）
    weight = phrase_weights.get(phrase, Config.DEFAULT_WEIGHT)
    
    # 验证权重是否为数字
    if not re.match(r'^\d+$', str(weight)):
        print(f"  警告: 权重值 '{weight}' 不是有效数字，使用默认值{Config.DEFAULT_WEIGHT}")
        weight = Config.DEFAULT_WEIGHT

    # 追加到文件
    try:
        with open(output_filename, 'a', encoding='utf-8') as f:
            f.write(f"{phrase}\t{code}\t{weight}\n")

        existing_phrases.add(phrase)
        print(f"  ✓ 已添加: {phrase} -> {code} (权重: {weight})")
        added = True

        return True, code
    except Exception as e:
        print(f"  错误: 无法写入文件: {e}")
        return False, str(e)

def interactive_input_mode(rule: int, char_codes: Dict[str, str], 
                          phrase_weights: Dict[str, str]) -> Tuple[int, int, str]:
    """
    交互式输入模式：用户输入词组，直到连续两个回车退出
    """
    output_filename = OUTPUT_FILE

    # 读取已存在的词语
    existing_phrases = read_existing_entries(output_filename)
    print(f"\n当前词库中已有 {len(existing_phrases)} 个词语")

    print("\n" + "=" * 50)
    print("交互式输入模式")
    if rule == 5:
        print("注意: 您选择了自由编码规则")
        print("  1. 可以输入任意字符的词组（汉字、字母、数字、标点等）")
        print("  2. 需要为每个词组输入自定义编码（只能包含小写字母和空格，任意长度）")
    elif rule == 6:
        print("注意: 您选择了五笔编码 + 拼音首字母规则")
        print("  编码 = 五笔编码(4码) + 拼音首字母")
    print("输入词组并回车，程序将自动编码并追加到词库")
    print("连续输入两个空行（直接按两次回车）退出程序")
    print("=" * 50)

    empty_line_count = 0
    added_count = 0
    fail_count = 0
    success_records = []

    while True:
        try:
            user_input = input(f"[输入词组 {added_count+1}]: ").strip()

            if user_input == "":
                empty_line_count += 1
                if empty_line_count >= 2:
                    print("检测到连续两个空行，退出输入模式...")
                    break
                else:
                    print("（输入空行，再输入一个空行将退出）")
                    continue
            else:
                empty_line_count = 0

                if is_file_path(user_input):
                    print(f"  检测到文件路径: {user_input}")
                    print("  请输入词组或连续两个空行退出")
                    continue

                success, result = interactive_single_input(user_input, rule, char_codes, phrase_weights, existing_phrases)
                if success:
                    added_count += 1
                    success_records.append({
                        'phrase': user_input,
                        'code': result,
                        'weight': phrase_weights.get(user_input, Config.DEFAULT_WEIGHT)
                    })
                elif result != "已存在":
                    fail_count += 1

        except KeyboardInterrupt:
            print("\n\n用户中断输入")
            break
        except Exception as e:
            print(f"  错误: {e}")
            fail_count += 1

    # 清理输出文件，确保没有空行
    if added_count > 0:
        clean_output_file(output_filename)

        # 生成记录文件
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

        # 确保记录目录存在
        if not os.path.exists(Config.RECORD_DIR):
            os.makedirs(Config.RECORD_DIR)
            print(f"已创建记录目录: {Config.RECORD_DIR}")

        record_file = os.path.join(Config.RECORD_DIR, f"interactive_processed_{timestamp}.txt")

        with open(record_file, 'w', encoding='utf-8') as f:
            f.write(f"# 交互式处理记录 - {timestamp}\n")
            f.write(f"# 编码规则: {rule}\n")
            f.write(f"# 成功添加: {added_count} 个词组\n")
            f.write(f"# 失败: {fail_count} 个\n")
            f.write(f"# 输出文件: {output_filename}\n")
            f.write("="*60 + "\n\n")

            if success_records:
                f.write("# 成功添加的词组:\n")
                f.write("="*60 + "\n")
                for record in success_records:
                    f.write(f"{record['phrase']}\t{record['code']}\t{record['weight']}\n")

        print(f"处理记录已保存到: {record_file}")

    return added_count, fail_count, output_filename

def file_batch_mode(rule: int, char_codes: Dict[str, str], 
                   phrase_weights: Dict[str, str], input_file: str) -> Tuple[int, int, str, str]:
    """
    文件批量处理模式：对文件中的每一行进行编码
    """
    output_filename = OUTPUT_FILE
    fail_filename = FAIL_FILE

    print(f"处理记录将保存到: {Config.RECORD_DIR}")

    # 对于规则五（自由编码），不支持文件批量处理
    if rule == 5:
        print("错误: 自由编码规则不支持文件批量处理模式")
        print("请使用交互式输入模式为每个词组输入自定义编码")
        return 0, 0, output_filename, fail_filename

    # 读取已存在的词语
    existing_phrases = read_existing_entries(output_filename)
    print(f"\n当前词库中已有 {len(existing_phrases)} 个词语")

    # 读取失败记录
    existing_fail_phrases = set()
    if os.path.exists(fail_filename):
        try:
            with open(fail_filename, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if line:
                        existing_fail_phrases.add(line)
        except Exception as e:
            print(f"读取失败文件 {fail_filename} 时出错: {e}")

    # 统计变量
    total_lines = 0
    added_count = 0
    fail_count = 0
    skipped_count = 0
    success_records = []
    fail_records = []

    print(f"\n开始处理文件: {input_file}")
    print("-" * 50)

    try:
        with open(input_file, 'r', encoding='utf-8') as infile:
            lines = infile.readlines()

        for line_num, line in enumerate(lines, 1):
            line = line.strip()
            total_lines += 1

            if not line:
                continue

            # 检查是否已存在于词库中
            if line in existing_phrases:
                skipped_count += 1
                print(f"  行 {line_num}: 词组 '{line}' 已存在于词库中，跳过")
                continue

            # 检查是否已存在于失败文件中
            if line in existing_fail_phrases:
                skipped_count += 1
                print(f"  行 {line_num}: 词组 '{line}' 已在失败文件中，跳过")
                continue

            # 对于规则六，需要检查是否有中文字符
            if rule == 6:
                chinese_chars = extract_chinese_chars(line)
                if not chinese_chars:
                    try:
                        with open(fail_filename, 'a', encoding='utf-8') as fail_file:
                            fail_file.write(f"{line}\n")
                        fail_count += 1
                        existing_fail_phrases.add(line)
                        fail_records.append({'phrase': line, 'reason': '不包含中文字符'})
                        print(f"  行 {line_num}: 词组 '{line}' 中不包含中文字符，保存到失败文件")
                    except Exception as e:
                        print(f"  行 {line_num}: 错误: 无法写入失败文件: {e}")
                    continue
            else:
                # 检查词组中的所有汉字是否都存在于编码表中
                if not check_all_chars_exist(line, char_codes):
                    try:
                        with open(fail_filename, 'a', encoding='utf-8') as fail_file:
                            fail_file.write(f"{line}\n")
                        fail_count += 1
                        existing_fail_phrases.add(line)
                        fail_records.append({'phrase': line, 'reason': '包含未编码的汉字'})
                        print(f"  行 {line_num}: 词组 '{line}' 中包含未编码的汉字，保存到失败文件")
                    except Exception as e:
                        print(f"  行 {line_num}: 错误: 无法写入失败文件: {e}")
                    continue

            # 提取中文字符用于编码
            chinese_chars = extract_chinese_chars(line)

            if not chinese_chars:
                fail_count += 1
                fail_records.append({'phrase': line, 'reason': '不包含中文字符'})
                print(f"  行 {line_num}: 词组 '{line}' 中不包含中文字符，跳过")
                continue

            # 生成编码（只使用中文字符）
            code = generate_wubi_code(chinese_chars, char_codes, rule)

            # 获取权重（使用最大权重）
            weight = phrase_weights.get(line, Config.DEFAULT_WEIGHT)
            
            # 验证权重是否为数字
            if not re.match(r'^\d+$', str(weight)):
                weight = Config.DEFAULT_WEIGHT

            # 追加到输出文件
            try:
                with open(output_filename, 'a', encoding='utf-8') as outfile:
                    outfile.write(f"{line}\t{code}\t{weight}\n")

                added_count += 1
                existing_phrases.add(line)
                success_records.append({'phrase': line, 'code': code, 'weight': weight})
                print(f"  ✓ 行 {line_num}: 已添加: {line} -> {code} (权重: {weight})")

            except Exception as e:
                print(f"  行 {line_num}: 错误: 无法写入输出文件: {e}")
                try:
                    with open(fail_filename, 'a', encoding='utf-8') as fail_file:
                        fail_file.write(f"{line}\n")
                    fail_count += 1
                    existing_fail_phrases.add(line)
                    fail_records.append({'phrase': line, 'reason': '文件写入错误'})
                except Exception as e2:
                    print(f"  行 {line_num}: 错误: 无法写入失败文件: {e2}")

        # 清理输出文件，确保没有空行
        if added_count > 0:
            clean_output_file(output_filename)

        # 清理失败文件，确保没有空行
        if fail_count > 0:
            clean_output_file(fail_filename)

        # 生成记录文件
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        base_name = os.path.splitext(os.path.basename(input_file))[0]

        # 确保记录目录存在
        if not os.path.exists(Config.RECORD_DIR):
            os.makedirs(Config.RECORD_DIR)
            print(f"已创建记录目录: {Config.RECORD_DIR}")

        record_file = os.path.join(Config.RECORD_DIR, f"{base_name}_processed_{timestamp}.txt")

        with open(record_file, 'w', encoding='utf-8') as f:
            f.write(f"# 批量处理记录 - {timestamp}\n")
            f.write(f"# 源文件: {os.path.basename(input_file)}\n")
            f.write(f"# 编码规则: {rule}\n")
            f.write(f"# 总行数: {total_lines}\n")
            f.write(f"# 成功添加: {added_count} 行\n")
            f.write(f"# 失败: {fail_count} 行\n")
            f.write(f"# 跳过: {skipped_count} 行\n")
            f.write(f"# 输出文件: {output_filename}\n")
            f.write(f"# 失败文件: {fail_filename}\n")
            f.write("="*60 + "\n\n")

            if success_records:
                f.write("# 成功添加的词组:\n")
                f.write("="*60 + "\n")
                for record in success_records:
                    f.write(f"{record['phrase']}\t{record['code']}\t{record['weight']}\n")
                f.write("\n")

            if fail_records:
                f.write("# 失败的词组:\n")
                f.write("="*60 + "\n")
                for record in fail_records:
                    f.write(f"{record['phrase']}\t{record['reason']}\n")

        print(f"处理记录已保存到: {record_file}")

        print("\n" + "=" * 50)
        print(f"文件处理完成:")
        print(f"  总行数: {total_lines}")
        print(f"  成功添加: {added_count}")
        print(f"  失败: {fail_count}")
        print(f"  跳过: {skipped_count}")
        print(f"  处理记录: {record_file}")
        print("=" * 50)

        return added_count, fail_count, output_filename, fail_filename

    except Exception as e:
        print(f"处理文件时出错: {e}")
        return 0, 0, output_filename, fail_filename

def auto_mode(rule: int, char_codes: Dict[str, str], phrase_weights: Dict[str, str]) -> Tuple[int, int, int]:
    """
    自动模式：根据用户输入自动判断是交互式还是文件批量处理
    """
    print("\n" + "=" * 50)
    print("自动模式")
    print("请输入词组或文件路径（可直接拖入文件）")
    print("输入词组：对单个词组进行编码")
    print("输入文件路径：对文件中的每一行进行批量编码")

    if rule == 5:
        print("注意: 您选择了自由编码规则，不支持文件批量处理")
        print("文件路径将被视为普通词组处理")
    elif rule == 6:
        print("注意: 您选择了五笔编码 + 拼音首字母规则")
        print("编码将包含五笔编码(4码) + 拼音首字母")

    print("连续输入两个空行退出程序")
    print("=" * 50)

    empty_line_count = 0
    interactive_count = 0
    file_count = 0
    fail_count = 0

    # 读取已存在的词语
    existing_phrases = read_existing_entries(OUTPUT_FILE)
    print(f"当前词库中已有 {len(existing_phrases)} 个词语")

    while True:
        try:
            user_input = input(f"[输入词组或文件路径]: ").strip()

            if user_input == "":
                empty_line_count += 1
                if empty_line_count >= 2:
                    print("检测到连续两个空行，退出程序...")
                    break
                else:
                    print("（输入空行，再输入一个空行将退出）")
                    continue
            else:
                empty_line_count = 0

                is_file = is_file_path(user_input)

                if is_file and rule not in [5, 6]:
                    print(f"✓ 检测到文件路径，进入文件批量处理模式")
                    file_path = user_input
                    if file_path.startswith('"') and file_path.endswith('"'):
                        file_path = file_path[1:-1]
                    elif file_path.startswith("'") and file_path.endswith("'"):
                        file_path = file_path[1:-1]

                    added, failed, output_file, fail_file = file_batch_mode(rule, char_codes, phrase_weights, file_path)
                    file_count += 1
                    if added > 0 or failed > 0:
                        print(f"  文件处理完成: 成功 {added} 条，失败 {failed} 条")
                        print(f"  成功条目已保存到: {output_file}")
                        if failed > 0:
                            print(f"  失败条目已保存到: {fail_file}")
                else:
                    if is_file and rule in [5, 6]:
                        print(f"⚠ 检测到文件路径，但规则{rule}不支持批量处理")
                        print(f"  将文件路径作为普通词组处理")

                    print(f"✓ 检测到词组，进入交互式处理模式")
                    success, result = interactive_single_input(user_input, rule, char_codes, phrase_weights, existing_phrases)
                    interactive_count += 1
                    if not success and result != "已存在":
                        fail_count += 1

        except KeyboardInterrupt:
            print("\n\n用户中断输入")
            break
        except Exception as e:
            print(f"  错误: {e}")
            fail_count += 1

    # 清理输出文件，确保没有空行
    if interactive_count > 0 or file_count > 0:
        clean_output_file(OUTPUT_FILE)

    return interactive_count, file_count, fail_count

def main() -> None:
    """主函数"""
    print("五笔词库生成工具 - 自动判断输入模式")
    print("-" * 50)
    
    # 检查并安装缺失的Python包
    check_and_install_packages()

    # 显示菜单让用户选择编码规则
    rule = select_encoding_rule()

    print("\n正在检查必要文件...")

    # 检查必要文件是否存在
    required_files = [SINGLE_CHAR_FILE, PHRASE_WEIGHT_FILE]
    missing_files = []
    for file in required_files:
        if not os.path.exists(file):
            missing_files.append(file)

    if missing_files:
        print("错误: 以下必要文件不存在:")
        for file in missing_files:
            print(f"  - {file}")
        print("\n请确保所有必要文件都在同一目录下")
        input("\n按Enter键退出...")
        return

    print("所有必要文件都存在")
    print("-" * 30)

    # 读取单字编码表
    char_codes = read_single_char_codes()
    if not char_codes:
        print("错误: 无法读取单字编码表，程序终止")
        input("\n按Enter键退出...")
        return

    # 读取词语权重表（保留最大权重）
    phrase_weights = read_phrase_weights()
    if not phrase_weights:
        print("警告: 词语权重表为空或无法读取，将使用默认权重")

    print("-" * 50)

    # 对于规则五（自由编码），直接进入交互式输入模式
    if rule == 5:
        print("注意: 您选择了自由编码规则，将进入交互式输入模式")
        print("您可以输入任意字符的词组，并为每个词组输入自定义编码")
        added_count, fail_count, output_filename = interactive_input_mode(rule, char_codes, phrase_weights)

        print("\n" + "=" * 50)
        print("程序执行完成")
        print("统计信息:")
        print(f"  成功添加: {added_count} 个词组")
        print(f"  失败: {fail_count} 个")
        print("=" * 50)
    else:
        # 进入自动模式
        interactive_count, file_count, fail_count = auto_mode(rule, char_codes, phrase_weights)

        print("\n" + "=" * 50)
        print("程序执行完成")
        print("统计信息:")
        print(f"  交互式处理词组: {interactive_count} 个")
        print(f"  批量处理文件: {file_count} 个")
        print(f"  失败条目: {fail_count} 个")
        print("=" * 50)

    # 检查是否有成功添加的词语
    if os.path.exists(OUTPUT_FILE):
        try:
            with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
                lines = f.readlines()
                if lines:
                    print("\n最后添加的几个词语:")
                    for line in lines[-min(len(lines), 5):]:
                        print(f"  {line.strip()}")
        except Exception as e:
            print(f"无法读取文件显示最后添加的词语: {e}")

        # 自动打开生成的词库文件
        print(f"\n正在打开词库文件: {OUTPUT_FILE}")
        open_file_with_default_app(OUTPUT_FILE)

    print("\n程序执行完成")
    print("=" * 50)
    input("\n按Enter键退出...")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n程序被用户中断")
        sys.exit(0)
    except Exception as e:
        print(f"\n程序运行时发生错误: {e}")
        import traceback
        traceback.print_exc()
        input("\n按Enter键退出...")