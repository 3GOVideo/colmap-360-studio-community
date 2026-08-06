# Contributing

Issues and pull requests are welcome. Please describe the panorama source,
operating system, Python/PyCOLMAP version, matching mode, and the number of
registered images when reporting reconstruction problems.

Before opening a pull request:

```bash
python -m py_compile reconstruct_360.py panorama_sfm_4_1_1.py
python reconstruct_360.py --help
```

Do not commit source panoramas, databases, reconstructions, PLY/SPZ files, or
Brush projects. Small synthetic fixtures may be proposed in a pull request.
