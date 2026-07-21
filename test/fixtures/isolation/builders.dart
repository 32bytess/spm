import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

// Mock 3rd party widget (will be stubbed)
class MockThirdPartyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container();
}

class CustomText extends StatelessWidget {
  final String text;
  CustomText(this.text);
  @override
  Widget build(BuildContext context) => Text(text);
}

class BuilderTestWidget extends StatefulWidget {
  @override
  State<BuilderTestWidget> createState() => _BuilderTestWidgetState();
}

class _BuilderTestWidgetState extends State<BuilderTestWidget> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CustomText('Hello'),
        CupertinoButton(child: Text('Click'), onPressed: () {}),
        Image.asset('assets/img.png'),
        const Placeholder(), // Should be kept as it's Flutter core
      ],
    );
  }
}
