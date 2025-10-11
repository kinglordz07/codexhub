# main.py
import subprocess
import os
import platform
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from tempfile import TemporaryDirectory

app = FastAPI()

# --- Enable CORS for Flutter Web & mobile
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Replace with your frontend URL in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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
                file_path = os.path.join(tmpdir, "temp.py")
                with open(file_path, "w") as f:
                    f.write(code)

                python_exec = "python3" if platform.system() != "Windows" else "python"
                result = subprocess.run(
                    [python_exec, file_path],
                    capture_output=True, text=True, timeout=10, cwd=tmpdir
                )
                output = result.stdout
                feedback = result.stderr

            elif language == "java":
                class_name = "Temp"
                file_path = os.path.join(tmpdir, f"{class_name}.java")
                # Wrap user code if not using Temp class
                user_code = code
                if "class " not in code:
                    user_code = f"public class {class_name} {{ public static void main(String[] args) {{ {code} }} }}"
                with open(file_path, "w") as f:
                    f.write(user_code)

                # Compile Java
                compile_result = subprocess.run(
                    ["javac", file_path],
                    capture_output=True, text=True, timeout=10, cwd=tmpdir
                )
                feedback += compile_result.stderr + compile_result.stdout

                if compile_result.returncode == 0:
                    run_result = subprocess.run(
                        ["java", "-cp", tmpdir, class_name],
                        capture_output=True, text=True, timeout=10, cwd=tmpdir
                    )
                    output += run_result.stdout
                    feedback += run_result.stderr

            elif language in ["csharp", "vbnet"]:
                ext = ".cs" if language == "csharp" else ".vb"
                compiler = "csc" if language == "csharp" else "vbc"
                exe_name = os.path.join(tmpdir, "Temp.exe")
                file_path = os.path.join(tmpdir, f"Temp{ext}")
                with open(file_path, "w") as f:
                    f.write(code)

                # Compile
                compile_result = subprocess.run(
                    [compiler, file_path],
                    capture_output=True, text=True, timeout=10, cwd=tmpdir
                )
                feedback += compile_result.stderr + compile_result.stdout

                if compile_result.returncode == 0:
                    exe_cmd = [exe_name]
                    if platform.system() != "Windows":
                        exe_cmd = ["mono", exe_name]

                    run_result = subprocess.run(
                        exe_cmd,
                        capture_output=True, text=True, timeout=10, cwd=tmpdir
                    )
                    output += run_result.stdout
                    feedback += run_result.stderr

            else:
                feedback = f"Unsupported language: {language}"

        except subprocess.TimeoutExpired:
            feedback = "Execution timed out."
        except Exception as e:
            feedback = str(e)

    return {"output": output.strip(), "feedback": feedback.strip()}

# --- Run FastAPI
if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
