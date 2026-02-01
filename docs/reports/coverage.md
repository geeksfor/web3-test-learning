# Coverage Progress Log

> 记录每次 coverage 跑出来的结果、缺口定位、补测计划与最终提升。  
> 建议每次补完测试后都追加一条记录（按日期）。

---

## 2026-02-01（Baseline）

### 命令
```bash
forge test -vvv
forge coverage

# 可选：生成 HTML 便于定位红线
forge coverage --report lcov
genhtml lcov.info --output-directory coverage
```

### 结果（最近一次）
```
src/Counter.sol     Lines 100.00% (6/6)   Statements 100.00% (3/3)   Branches 100.00% (0/0)  Funcs 100.00% (3/3)
src/SimpleERC20.sol Lines 89.86% (62/69)  Statements 86.15% (56/65)  Branches 61.54% (8/13)  Funcs 81.25% (13/16)
Total               Lines 90.67% (68/75)  Statements 86.76% (59/68)  Branches 61.54% (8/13)  Funcs 84.21% (16/19)
```

### 结论
- `SimpleERC20.sol` 的 **branches（8/13）** 与 **funcs（13/16）** 仍有明显提升空间。
- 下一步优先做：用 `genhtml` 打开 `coverage/index.html`，精确定位未覆盖的 if 分支与未调用函数。

### 待补清单（候选）
> 以 HTML 标红为准，以下是常见补漏方向（可能不全部存在于你的实现中）：
- transfer / transferFrom / approve：zero address 分支
- amount==0 分支（允许并 emit / 或 revert）
- burnFrom：无限 allowance 特判分支（`type(uint256).max`）
- view/辅助函数未被调用（导致 funcs 未满）
