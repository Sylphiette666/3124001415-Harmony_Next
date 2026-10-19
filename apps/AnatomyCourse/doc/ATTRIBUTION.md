# 第三方来源与许可

Web 基础项目：[ashemag/human-atlas](https://github.com/ashemag/human-atlas)。移植基线为 `1c38bf35c254a891200d3cedecfd57abebe83d8d`。上游 MIT 许可原文保存在 `web/LICENSE`，元数据见 `web/UPSTREAM.json`。

解剖模型：**BodyParts3D, © The Database Center for Life Science**，遵循 [CC Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/)。模型已经过上游简化、打包和系统着色，本项目增加原生容器、搜索和学习功能。

数据来源：[BodyParts3D](https://lifesciencedb.jp/bp3d/)、[数据许可](https://dbarchive.biosciencedbc.jp/en/bodyparts3d/lic.html)。原始署名文件保留在 `web/public/ATTRIBUTION.md`，随 Web 构建打包。应用“学习 → 关于”和 Web“来源与许可”可查看署名。

React、Three.js、Vite 及其他依赖的版本由 `web/package-lock.json` 固定，其许可保留在对应软件包内。不要移除上游代码和模型的许可证、版权或署名信息。
