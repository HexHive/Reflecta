// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Fuzzilli

struct Profile {
    var lang: String = "js"

    let getProcessArguments: (_: Bool) -> [String]
    let processEnv: [String: String]
    let maxExecsBeforeRespawn: Int
    // Timeout is in milliseconds.
    let timeout: Int
    let codePrefix: String
    let codeSuffix: String
    let ecmaVersion: ECMAScriptVersion

    // JavaScript code snippets that cause a crash in the target engine.
    // Used to verify that crashes can be detected.
    let crashTests: [String]

    let additionalCodeGenerators: [(CodeGenerator, Int)]
    let additionalProgramTemplates: WeightedList<ProgramTemplate>

    let disabledCodeGenerators: [String]

    let additionalBuiltins: [String: JSType]
}

func makeReflectionProfile(lang: String, prefix: String) -> Profile {
    return Profile(
        lang: lang,
        getProcessArguments: { (randomizingArguments: Bool) -> [String] in
            return []
        },
        processEnv: [
            "ASAN_OPTIONS":
                "symbolize=0,detect_leaks=0,allocator_may_return_null=1,abort_on_error=1"
        ],
        maxExecsBeforeRespawn: 1000,
        timeout: 300,
        codePrefix: prefix,
        codeSuffix: "",
        ecmaVersion: ECMAScriptVersion.es6,
        crashTests: lang == "php" ? ["$reflecta->crash()"] : ["Reflecta.crash()"],
        additionalCodeGenerators: [],
        additionalProgramTemplates: WeightedList<ProgramTemplate>([]),
        disabledCodeGenerators: [],
        additionalBuiltins: [:]
    )
}

let scriptdir = "/workspaces/Reflecta/scripts"
let pythonProfile = makeReflectionProfile(
    lang: "python",
    prefix:
        """
        import sys; sys.path.append('\(scriptdir)'); from reflecta import *;
        """
)

let phpProfile = makeReflectionProfile(
    lang: "php",
    prefix:
        """
        <?php
        require_once('\(scriptdir)/reflecta.php');
        """
)

let rubyProfile = makeReflectionProfile(
    lang: "ruby",
    prefix:
        """
        require '\(scriptdir)/reflecta.rb'
        """
)

let v8rProfile = makeReflectionProfile(
    lang: "js",
    prefix:
        """
        load("\(scriptdir)/reflecta.js");
        """
)

let profiles = [
    "qtjs": qtjsProfile,
    "qjs": qjsProfile,
    "jsc": jscProfile,
    "spidermonkey": spidermonkeyProfile,
    "v8": v8Profile,
    "duktape": duktapeProfile,
    "jerryscript": jerryscriptProfile,
    "xs": xsProfile,
    "v8r": v8rProfile,
    "ruby": rubyProfile,
    "php": phpProfile,
    "python": pythonProfile,
]
