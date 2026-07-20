import 'package:ai_reader/services/library_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('导入文件名清洗', () {
    test('「书名+(作者)+」拼接格式 → 书名与作者分离', () {
      final (title, author) =
          LibraryStore.cleanImportTitle('小岛经济学+(彼得·希夫,安德鲁·希夫)+');
      expect(title, '小岛经济学');
      expect(author, '彼得·希夫,安德鲁·希夫');
    });

    test('下划线与多余空格清理', () {
      final (title, author) = LibraryStore.cleanImportTitle('国富论__上册');
      expect(title, '国富论 上册');
      expect(author, isNull);
    });

    test('分册括号不误当作者', () {
      final (title, author) = LibraryStore.cleanImportTitle('傲慢与偏见(上)');
      expect(title, '傲慢与偏见(上)');
      expect(author, isNull);
      final (t2, a2) = LibraryStore.cleanImportTitle('史记(第三册)');
      expect(t2, '史记(第三册)');
      expect(a2, isNull);
    });

    test('普通文件名原样保留', () {
      final (title, author) = LibraryStore.cleanImportTitle('林间试读');
      expect(title, '林间试读');
      expect(author, isNull);
    });

    test('英文括号作者', () {
      final (title, author) =
          LibraryStore.cleanImportTitle('The Wealth of Nations (Adam Smith)');
      expect(title, 'The Wealth of Nations');
      expect(author, 'Adam Smith');
    });
  });
}
