// Copyright (c) .NET Foundation and contributors. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for full license information.

using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;

namespace Microsoft.Extensions.DependencyModel
{
    public class CompilationLibrary : Library
    {
        private static Lazy<Assembly> _entryAssembly = new Lazy<Assembly>(GetEntryAssembly);

        private static string _nugetPackages = Environment.GetEnvironmentVariable("NUGET_PACKAGES");
        private static string _packageCache = Environment.GetEnvironmentVariable("DOTNET_PACKAGES_CACHE");

        public CompilationLibrary(string libraryType, string packageName, string version, string hash, string[] assemblies, Dependency[] dependencies, bool serviceable)
            : base(libraryType, packageName, version, hash,  dependencies, serviceable)
        {
            Assemblies = assemblies;
        }

        public IReadOnlyList<string> Assemblies { get; }

        public IEnumerable<string> ResolveReferencePaths()
        {
            var entryAssembly = _entryAssembly.Value;
            var entryAssemblyName = entryAssembly.GetName().Name;

            string basePath;
            string fullName;

            if (TryResolvePackagePath(out basePath))
            {
                foreach (var assembly in Assemblies)
                {
                    if (!TryResolveAssemblyFile(basePath, assembly, out fullName))
                    {
                        throw new InvalidOperationException($"Can not find assembly file at '{fullName}'");
                    }
                    yield return fullName;
                }
            }
            else
            {
                var appBase = Path.GetDirectoryName(entryAssembly.Location);
                var refsPath = Path.Combine(appBase, "refs");
                var checkRefs = Directory.Exists(refsPath);

                foreach (var assembly in Assemblies)
                {
                    var assemblyFile = Path.GetFileName(assembly);
                    if (checkRefs && TryResolveAssemblyFile(refsPath, assemblyFile, out fullName))
                    {
                        yield return fullName;
                    }
                    else if (TryResolveAssemblyFile(appBase, assemblyFile, out fullName))
                    {
                        yield return fullName;
                    }
                    else
                    {
                        var errorMessage = $"Can not find assembly file {assemblyFile} at '{basePath}'";
                        if (checkRefs)
                        {
                            errorMessage += $", '{refsPath}'";
                        }
                        throw new InvalidOperationException(errorMessage);
                    }
                }
            }
        }

        private bool TryResolveAssemblyFile(string basePath, string assemblyPath, out string fullName)
        {
            fullName = Path.Combine(basePath, assemblyPath, Version);
            if (File.Exists(fullName))
            {
                return true;
            }
            return false;
        }

        private bool TryResolvePackagePath(out string packagePath)
        {
            packagePath = null;

            if (!string.IsNullOrEmpty(_packageCache))
            {
                var hashSplitterPos = Hash.IndexOf('-');
                if (hashSplitterPos <= 0 || hashSplitterPos == Hash.Length - 1)
                {
                    throw new InvalidOperationException($"Invalid hash entry '{Hash}' for package '{PackageName}'");
                }

                var hashAlgorithm = Hash.Substring(0, hashSplitterPos);

                var cacheHashPath = Path.Combine(_packageCache, $"{PackageName}.{Version}.nupkg.{hashAlgorithm}");

                if (File.Exists(cacheHashPath) &&
                    File.ReadAllText(cacheHashPath) == Hash.Substring(hashSplitterPos + 1))
                {
                    if (TryResolvePackagePath(_nugetPackages, out packagePath))
                    {
                        return true;
                    }
                }
            }
            if (!string.IsNullOrEmpty(_nugetPackages) &&
                TryResolvePackagePath(_nugetPackages, out packagePath))
            {
                return true;
            }
            return false;
        }

        private bool TryResolvePackagePath(string basePath, out string packagePath)
        {
            packagePath = Path.Combine(basePath, PackageName, Version);
            if (Directory.Exists(packagePath))
            {
                return true;
            }
            return false;
        }

        private static Assembly GetEntryAssembly()
        {
            var entryAssembly = (Assembly)typeof(Assembly).GetTypeInfo().GetDeclaredMethod("GetEntryAssembly").Invoke(null, null);
            if (entryAssembly == null)
            {
                throw new InvalidOperationException("Could not determine entry assembly");
            }
            return entryAssembly;
        }
    }
}