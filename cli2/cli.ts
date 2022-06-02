#!/usr/bin/env node

import * as fs from "fs";
import * as util from "util";
import * as path from "path";
import * as FileChanges from "./FileChanges";

const fsExists = util.promisify(fs.exists);
const fsWriteFile = util.promisify(fs.writeFile);
const fsMakeDir = util.promisify(fs.mkdir);
const fsReadFile = util.promisify(fs.readFile);
const readdir = util.promisify(fs.readdir);

const worker = require("./../Morphir.Elm.CLI").Elm.Morphir.Elm.CLI.init();

interface MorphirJson {
  name: string;
  sourceDirectory: string;
  exposedModules: string[];
}

async function make(
  projectDir: string,
  options: any
): Promise<string | undefined> {
  // Morphir specific files expected to be in the project directory
  const morphirJsonPath: string = path.join(projectDir, "morphir.json");
  const hashFilePath: string = path.join(projectDir, "morphir-hashes.json");
  const morphirIrPath: string = path.join(projectDir, "morphir-ir.json");

  // Load the `morphir.json` file that describes the project
  const morphirJson: MorphirJson = JSON.parse(
    (await fsReadFile(morphirJsonPath)).toString()
  );

  // Check if there is an existing IR
  if ((await fsExists(morphirIrPath)) && (await fsExists(hashFilePath))) {
    const oldContentHashes = await readContentHashes(hashFilePath);
    const fileChanges = await FileChanges.detectChanges(
      oldContentHashes,
      path.join(projectDir, morphirJson.sourceDirectory)
    );
    if (reportFileChangeStats(fileChanges)) {
      console.log(
        "There were file changes and there is an existing IR. Building incrementally."
      );
      const previousIR: string = (await fsReadFile(morphirIrPath)).toString();
      const updatedIR: string = await buildIncrementally(
        morphirJson,
        fileChanges,
        options,
        previousIR
      );
      await writeContentHashes(
        hashFilePath,
        FileChanges.toContentHashes(fileChanges)
      );
      return updatedIR;
    } else {
      console.log(
        "There were no file changes and there is an existing IR. No actions needed."
      );
    }
  } else {
    console.log("There is no existing IR Or Hash file. Building from scratch.");
    // We invoke file change detection but pass in no hashes which will generate inserts only
    const fileChanges = await FileChanges.detectChanges(
      new Map(),
      path.join(projectDir, morphirJson.sourceDirectory)
    );
    const fileSnapshot = FileChanges.toFileSnapshotJson(fileChanges);
    const newIR: string = await buildFromScratch(
      morphirJson,
      fileSnapshot,
      options
    );
    await writeContentHashes(
      hashFilePath,
      FileChanges.toContentHashes(fileChanges)
    );
    return newIR;
  }
}

async function buildFromScratch(
  morphirJson: any,
  fileSnapshot: { [index: string]: string },
  options: any
): Promise<string> {
  return new Promise((resolve, reject) => {
    worker.ports.decodeFailed.subscribe((err: any) => {
      reject(err);
    });

    worker.ports.buildFailed.subscribe((err: any) => {
      reject(err);
    });

    worker.ports.reportProgress.subscribe((message: any) => {
      console.log(message);
    });

    worker.ports.buildCompleted.subscribe(([err, ok]: any) => {
      if (err) {
        reject(err);
      } else {
        resolve(JSON.stringify(ok, null, 4));
      }
    });

    const opts = {
      typesOnly: options.typesOnly,
    };

    worker.ports.buildFromScratch.send({
      options: opts,
      packageInfo: morphirJson,
      fileSnapshot: fileSnapshot,
    });
  });
}

async function buildIncrementally(
  morphirJson: any,
  fileChanges: FileChanges.FileChanges,
  options: any,
  previousIR: string
): Promise<string> {
  return new Promise((resolve, reject) => {
    worker.ports.decodeFailed.subscribe((err: any) => {
      reject(err);
    });

    worker.ports.buildFailed.subscribe((err: any) => {
      reject(err);
    });

    worker.ports.reportProgress.subscribe((message: any) => {
      console.log(message);
    });

    worker.ports.buildCompleted.subscribe(([err, ok]: any) => {
      if (err) {
        reject(err);
      } else {
        resolve(JSON.stringify(ok, null, 4));
      }
    });

    const opts = {
      typesOnly: options.typesOnly,
    };

    let maybeDistribution = null;
    if (previousIR) {
      maybeDistribution = JSON.parse(previousIR);
    }

    worker.ports.buildIncrementally.send({
      options: opts,
      packageInfo: morphirJson,
      fileChanges: FileChanges.toFileChangesJson(fileChanges),
      distribution: maybeDistribution,
    });
  });
}

/**
 * Read content hashes from a file.
 *
 * @param filePath file path to read hashes from
 * @returns map of hashes
 */
async function readContentHashes(
  filePath: string
): Promise<Map<FileChanges.Path, FileChanges.Hash>> {
  // Check if the file exists
  if (await fsExists(filePath)) {
    const contentHashesJson = JSON.parse(
      (await fsReadFile(filePath)).toString()
    );
    const contentHashesMap: Map<FileChanges.Path, FileChanges.Hash> = new Map<
      FileChanges.Path,
      FileChanges.Hash
    >();
    for (let path in contentHashesJson) {
      contentHashesMap.set(path, contentHashesJson[path]);
    }
    return contentHashesMap;
  } else {
    return new Map<FileChanges.Path, FileChanges.Hash>();
  }
}

/**
 * Write content hashes into a file.
 *
 * @param filePath file path to read hashes from
 * @returns map of hashes
 */
async function writeContentHashes(
  filePath: string,
  hashes: Map<FileChanges.Path, FileChanges.Hash>
): Promise<void> {
  const jsonObject: { [index: string]: string } = {};
  for (let [path, hash] of hashes) {
    jsonObject[path] = hash;
  }
  await writeFile(filePath, JSON.stringify(jsonObject, null, 4));
}

function reportFileChangeStats(fileChanges: FileChanges.FileChanges): boolean {
  const stats: FileChanges.Stats = FileChanges.toStats(fileChanges);
  if (FileChanges.hasChanges(stats)) {
    const message = [
      `- inserted:  ${stats.inserted}`,
      `- updated:   ${stats.updated}`,
      `- deleted:   ${stats.deleted}`,
      `- unchanged: ${stats.unchanged}`,
    ].join("\n  ");
    console.log(`The following file changes were detected:\n  ${message}`);
    return true;
  } else {
    console.log(`No file changes were detected.`);
    return false;
  }
}

interface CommandOptions {
  modulesToInclude: string;
  targetVersion: string;
}
interface WorkerOptions {
  limitToModules?: string[];
}
function mapCommandToWorkerOptions(options: CommandOptions): WorkerOptions {
  return {
    limitToModules: options.modulesToInclude
      ? options.modulesToInclude.split(",")
      : undefined,
  };
}

const gen = async (
  input: string,
  outputPath: string,
  options: CommandOptions
) => {
  await fsMakeDir(outputPath, {
    recursive: true,
  });
  const morphirIrJson: Buffer = await fsReadFile(path.resolve(input));
  const workerOptions: WorkerOptions = mapCommandToWorkerOptions(options);
  // opts.limitToModules = options.modulesToInclude ? options.modulesToInclude.split(',') : undefined
  const generatedFiles: string[] = await generate(
    workerOptions,
    JSON.parse(morphirIrJson.toString())
  );

  const writePromises = generatedFiles.map(
    async ([[dirPath, fileName], content]: any) => {
      const fileDir: string = dirPath.reduce(
        (accum: string, next: string) => path.join(accum, next),
        outputPath
      );
      const filePath: string = path.join(fileDir, fileName);
      if (await fileExist(filePath)) {
        await fsWriteFile(filePath, content);
        console.log(`UPDATE - ${filePath}`);
      } else {
        await fsMakeDir(fileDir, {
          recursive: true,
        });
        await fsWriteFile(filePath, content);
        console.log(`INSERT - ${filePath}`);
      }
    }
  );
  const filesToDelete = await findFilesToDelete(outputPath, generatedFiles);
  const deletePromises = filesToDelete.map(async (fileToDelete: string) => {
    console.log(`DELETE - ${fileToDelete}`);
    return fs.unlinkSync(fileToDelete);
  });
  copyRedistributables(options, outputPath);
  return Promise.all(writePromises.concat(deletePromises));
};

const generate = async (
  options: WorkerOptions,
  ir: string
): Promise<string[]> => {
  return new Promise((resolve, reject) => {
    worker.ports.jsonDecodeError.subscribe((err: any) => {
      reject(err);
    });
    worker.ports.generateResult.subscribe(([err, ok]: any) => {
      if (err) {
        reject(err);
      } else {
        resolve(ok);
      }
    });

    worker.ports.generate.send([options, ir]);
  });
};

const fileExist = async (filePath: string) => {
  return new Promise((resolve, reject) => {
    fs.access(filePath, fs.constants.F_OK, (err) => {
      if (err) {
        resolve(false);
      } else {
        resolve(true);
      }
    });
  });
};

const findFilesToDelete = async (outputPath: string, fileMap: string[]) => {
  const readDir = async function (
    currentDir: string,
    generatedFiles: string[]
  ) {
    const entries: fs.Dirent[] = await readdir(currentDir, {
      withFileTypes: true,
    });
    const filesToDelete = entries
      .filter((entry) => {
        const entryPath: string = path.join(currentDir, entry.name);
        return entry.isFile() && !generatedFiles.includes(entryPath);
      })
      .map((entry) => path.join(currentDir, entry.name));
    const subDirFilesToDelete: Promise<string[]> = entries
      .filter((entry) => entry.isDirectory())
      .map((entry) =>
        readDir(path.join(currentDir, entry.name), generatedFiles)
      )
      .reduce(async (soFarPromise, nextPromise) => {
        const soFar = await soFarPromise;
        const next = await nextPromise;
        return soFar.concat(next);
      }, Promise.resolve([]));
    return filesToDelete.concat(await subDirFilesToDelete);
  };
  const files = fileMap.map(([[dirPath, fileName], content]: any) => {
    const fileDir = dirPath.reduce(
      (accum: string, next: string) => path.join(accum, next),
      outputPath
    );
    return path.resolve(fileDir, fileName);
  });
  return Promise.all(await readDir(outputPath, files));
};

function copyRedistributables(options: CommandOptions, outputPath: string) {
  const copyFiles = (src: string, dest: string) => {
    const sourceDirectory: string = path.join(
      path.dirname(__dirname),
      "redistributable",
      src
    );
    copyRecursiveSync(sourceDirectory, outputPath);
  };
  copyFiles("Scala/sdk/src", outputPath);
  copyFiles(`Scala/sdk/src-${options.targetVersion}`, outputPath);
}

function copyRecursiveSync(src: string, dest: string) {
  const exists = fs.existsSync(src);
  if (exists) {
    const stats = exists && fs.statSync(src);
    const isDirectory = exists && stats.isDirectory();
    if (isDirectory) {
      if (!fs.existsSync(dest)) fs.mkdirSync(dest);
      fs.readdirSync(src).forEach(function (childItemName) {
        copyRecursiveSync(
          path.join(src, childItemName),
          path.join(dest, childItemName)
        );
      });
    } else {
      fs.copyFileSync(src, dest);
      console.log(`COPY - ${dest}`);
    }
  }
}

async function writeFile(filePath: string, content: string) {
  await fsMakeDir(path.dirname(filePath), {
    recursive: true,
  });
  return await fsWriteFile(filePath, content);
}

export = { make, writeFile, gen };
