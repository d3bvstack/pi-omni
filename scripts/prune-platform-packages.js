#!/usr/bin/env node
//
// Drops the node_modules entries that cannot run on this platform.
//
// The Pi package ships an npm-shrinkwrap.json, and npm installs a shrinkwrap
// verbatim rather than filtering optional dependencies by os and cpu. esbuild
// declares one optional dependency per operating system and architecture, so all
// twenty-six of them land in the tree, 285 MB of a 610 MB layer, and exactly one
// is usable. Deleting the shrinkwrap would fix that too, but it would resolve
// every transitive dependency to a fresh `^` range on each build, so the tree is
// kept as pinned and pruned afterwards by the rule npm would have applied.
//
//   node scripts/prune-platform-packages.js [DIR]   default: the current directory
//
// Prints one line per removed package and a total. Exits non-zero if DIR does not
// exist, so a wrong argument fails the build instead of pruning nothing.

const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(process.argv[2] || process.cwd());
const { platform, arch } = process;

let removed = 0;
let freed = 0;

function megabytes(bytes) {
    return `${(bytes / 1048576).toFixed(1)} MB`;
}

// npm's rule for the `os` and `cpu` manifest fields: a package is skipped when
// the running value is absent from the list. An entry may be negated with `!`, so
// `['!linux']` fits every platform except linux. Absent or empty means no
// constraint, which every platform satisfies.
function fits(list, value) {
    if (list === undefined || list === null) {
        return true;
    }
    const entries = [list].flat().map(String);
    if (entries.length === 0) {
        return true;
    }
    return entries.some((entry) => (entry.startsWith('!') ? entry.slice(1) !== value : entry === value));
}

function diskUsage(dir) {
    let total = 0;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
            total += diskUsage(full);
        } else if (entry.isFile()) {
            total += fs.statSync(full).size;
        }
    }
    return total;
}

// A null return means "keep". A manifest that cannot be parsed is not a package
// this script can judge, so it is left alone rather than deleted.
function rejectedBy(manifest) {
    if (!fits(manifest.os, platform) || !fits(manifest.cpu, arch)) {
        return manifest;
    }
    return null;
}

function visit(dir) {
    const manifest = path.join(dir, 'package.json');
    if (fs.existsSync(manifest)) {
        let parsed;
        try {
            parsed = JSON.parse(fs.readFileSync(manifest, 'utf8'));
        } catch {
            return;
        }
        if (rejectedBy(parsed)) {
            const size = diskUsage(dir);
            fs.rmSync(dir, { recursive: true, force: true });
            removed += 1;
            freed += size;
            console.log(`  removed ${path.relative(root, dir)} (${megabytes(size)})`);
            return;
        }
    }
    sweep(path.join(dir, 'node_modules'));
}

// `node_modules` at one level: `@scope` directories hold packages and are
// descended into as scopes, not as packages themselves. Anything that is not a
// real directory is skipped, so a symlinked package is never followed.
function sweep(nodeModules) {
    let entries;
    try {
        entries = fs.readdirSync(nodeModules, { withFileTypes: true });
    } catch {
        return;
    }
    for (const entry of entries) {
        if (!entry.isDirectory() || entry.name.startsWith('.')) {
            continue;
        }
        const full = path.join(nodeModules, entry.name);
        if (!entry.name.startsWith('@')) {
            visit(full);
            continue;
        }
        for (const scoped of fs.readdirSync(full, { withFileTypes: true })) {
            if (scoped.isDirectory()) {
                visit(path.join(full, scoped.name));
            }
        }
    }
}

if (!fs.existsSync(root)) {
    console.error(`prune-platform-packages: ${root} does not exist`);
    process.exit(1);
}

sweep(root);
console.log(`pruned ${removed} package(s) for ${platform}/${arch}, freeing ${megabytes(freed)}`);
