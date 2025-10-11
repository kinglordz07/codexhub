import subprocess
import os
import platform
from fastapi import FastAPI
from pydantic import BaseModel
from tempfile import TemporaryDirectory

app = FastAPI()

class CodeRequest(BaseModel):
    code: str
    language: str

@app.post("/execute")
async def execute_code(req: CodeRequest):
    code = req.code
    language = req.language.lower()
    output = ""
    feedback = ""

    with TemporaryDirectory() as tmpdir:
        try:
            if language == "python":
                file_name = os.path.join(tmpdir, "temp.py")
                with open(file_name, "w") as f:
                    f.write(code)

                python_exec = "python3" if platform.system() != "Windows" else "python"
                result = subprocess.run(
                    [python_exec, file_name],
                    capture_output=True, text=True, timeout=10
                )
                output = result.stdout
                feedback = result.stderr

            elif language == "java":
                file_name = os.path.join(tmpdir, "Temp.java")
                class_name = "Temp"
                with open(file_name, "w") as f:
                    f.write(code)

                # Compile Java
                compile_result = subprocess.run(
                    ["javac", file_name],
                    capture_output=True, text=True, timeout=10
                )
                output += compile_result.stdout
                feedback += compile_result.stderr

                if compile_result.returncode == 0:
                    # Run Java with classpath
                    run_result = subprocess.run(
                        ["java", "-cp", tmpdir, class_name],
                        capture_output=True, text=True, timeout=10
                    )
                    output += run_result.stdout
                    feedback += run_result.stderr

            elif language in ["csharp", "vbnet"]:
                ext = ".cs" if language == "csharp" else ".vb"
                file_name = os.path.join(tmpdir, f"Temp{ext}")
                exe_name = os.path.join(tmpdir, "Temp.exe")
                with open(file_name, "w") as f:
                    f.write(code)

                # Compile
                compiler = "csc" if language == "csharp" else "vbc"
                compile_result = subprocess.run(
                    [compiler, file_name],
                    capture_output=True, text=True, timeout=10
                )
                output += compile_result.stdout
                feedback += compile_result.stderr

                if compile_result.returncode == 0:
                    # Run compiled exe
                    exe_cmd = [exe_name]
                    if platform.system() != "Windows":
                        exe_cmd = ["mono", exe_name]

                    run_result = subprocess.run(
                        exe_cmd,
                        capture_output=True, text=True, timeout=10
                    )
                    output += run_result.stdout
                    feedback += run_result.stderr

            else:
                feedback = f"Unsupported language: {language}"

        except subprocess.TimeoutExpired:
            feedback = "Execution timed out."
        except Exception as e:
            feedback = str(e)

    return {"output": output, "feedback": feedback}
