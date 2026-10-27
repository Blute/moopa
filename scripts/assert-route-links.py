#!/usr/bin/env python3
"""Fail unless every package's route_links.json describes exactly the routes the package owns.

    python3 code/moopa/scripts/assert-route-links.py [--format] [code]   # in a project
    python3 scripts/assert-route-links.py [--format] .                   # in Moopa itself

route_links.json records which pages each route links to; System -> Route Access draws the map
from it (format: docs/route-links.md). A package opts in by having the file, at its root beside
routes/: code/apps/<app>/route_links.json, code/shared/route_links.json, or Moopa's own. For each
one this checks that:

  1. its keys are exactly the package's route files: none missing, none left from deleted routes;
  2. every link is a route served by every app that loads the package;
  3. keys and links are sorted and unique, and no route links to itself.

Hub serves Moopa's System pages (moopa/routes/sysadmin) as well as its own and shared routes, so
Hub's routes may link to them; they are listed only in Moopa's file. /sysadmin is reserved for
them: a project route file under routes/sysadmin, copied or linked, is reported too, as Moopa
refuses to start with one. Route URLs are derived the way Moopa derives them
(internal/routing/route_url.cfc): the path under routes/ without .cfc, with a trailing /index
dropped, so routes/index.cfc is /.

Given a folder with no apps/ but a routes/ folder (Moopa's own checkout), it checks Moopa's file:
its links must stay within Moopa's routes.

--format rewrites each file with its keys and links sorted and de-duplicated, then checks.

scripts/test_assert_route_links.sh covers it.
"""
import json
import pathlib
import sys

FIX = 'Update it with the route-map skill (code/moopa/.agents/skills/route-map/SKILL.md).'
SYSTEM_PREFIX = '/sysadmin'


def route_url(relative):
    """A route file's URL, as route_url.cfc canonicalises it."""
    parts = [part for part in relative.with_suffix('').as_posix().split('/') if part]
    if parts and parts[-1] == 'index':
        parts = parts[:-1]
    return '/' + '/'.join(parts)


def route_urls(routes_dir):
    """The URLs of the .cfc route files under routes_dir, following symlinks as Moopa does."""
    urls = set()
    if not routes_dir.is_dir():
        return urls
    stack = [routes_dir]
    while stack:
        folder = stack.pop()
        for entry in folder.iterdir():
            if entry.is_dir():
                stack.append(entry)
            elif entry.suffix == '.cfc':
                urls.add(route_url(entry.relative_to(routes_dir)))
    return urls


def is_system(url):
    return url == SYSTEM_PREFIX or url.startswith(SYSTEM_PREFIX + '/')


def read_links(path):
    """The file's object as [(key, value)] in file order; a ValueError for anything malformed."""
    try:
        pairs = json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=lambda items: items)
    except json.JSONDecodeError as error:
        raise ValueError(f'is not valid JSON: {error}')
    if not isinstance(pairs, list):
        raise ValueError('must be an object of route URL to linked route URLs')
    seen = set()
    for key, value in pairs:
        if key in seen:
            raise ValueError(f'lists {key} twice')
        seen.add(key)
        if not isinstance(value, list) or not all(isinstance(target, str) for target in value):
            raise ValueError(f'{key} must map to an array of route URLs')
    return pairs


def format_file(path):
    pairs = read_links(path)
    tidy = {key: sorted(set(value) - {key}) for key, value in sorted(pairs)}
    path.write_text(json.dumps(tidy, indent=2) + '\n', encoding='utf-8')


def check_package(name, root, owned, served):
    """The problems with one package's route_links.json, as lines."""
    path = root / 'route_links.json'
    try:
        pairs = read_links(path)
    except ValueError as error:
        return [f'{path} {error}']

    problems = []
    keys = [key for key, _ in pairs]
    links = dict(pairs)

    for url in sorted(owned - set(keys)):
        problems.append(f'{name}: {url} is a route file but has no entry (unmapped)')
    for url in sorted(set(keys) - owned):
        problems.append(f'{name}: {url} has an entry but no route file in {name}')
    if keys != sorted(keys):
        problems.append(f'{name}: keys are not in sorted order (run with --format)')

    for key in keys:
        targets = links[key]
        if targets != sorted(set(targets)):
            problems.append(f'{name}: {key} links are not sorted and unique (run with --format)')
        if key in targets:
            problems.append(f'{name}: {key} links to itself')
        for target in sorted(set(targets) - served - {key}):
            problems.append(f'{name}: {key} links to {target}, which is not a route every app loading {name} serves')
    return problems


def packages_in_project(code):
    """(name, root, owned routes, served routes) for each project package, and reserved-route problems."""
    moopa_routes = route_urls(code / 'moopa' / 'routes')
    shared_routes = route_urls(code / 'shared' / 'routes')
    apps = sorted(path for path in (code / 'apps').iterdir() if path.is_dir())
    owned_by_app = {app.name: route_urls(app / 'routes') for app in apps}
    served_by_app = {
        app.name: owned_by_app[app.name] | shared_routes | (moopa_routes if app.name == 'hub' else set())
        for app in apps
    }

    problems = []
    for name, owned in [(f'apps/{app.name}', owned_by_app[app.name]) for app in apps] + [('shared', shared_routes)]:
        for url in sorted(filter(is_system, owned)):
            problems.append(f'{name}: {url} is under /sysadmin, which is Moopa\'s; delete the project\'s routes/sysadmin (Hub serves Moopa\'s own)')

    packages = [(f'apps/{app.name}', app, owned_by_app[app.name], served_by_app[app.name]) for app in apps]
    if served_by_app:
        packages.append(('shared', code / 'shared', shared_routes, set.intersection(*served_by_app.values())))
    return packages, problems


def main(argv):
    args = [arg for arg in argv if arg != '--format']
    if len(args) > 1:
        sys.exit('usage: assert-route-links.py [--format] [code directory | Moopa checkout]')
    code = pathlib.Path(args[0] if args else 'code')

    if (code / 'apps').is_dir():
        packages, problems = packages_in_project(code)
    elif (code / 'routes').is_dir():
        moopa_routes = route_urls(code / 'routes')
        packages, problems = [('moopa', code, moopa_routes, moopa_routes)], []
    else:
        sys.exit(f'{code} has neither an apps/ folder (a project\'s code) nor a routes/ folder (Moopa)')

    for name, root, owned, served in packages:
        if not (root / 'route_links.json').is_file():
            continue
        if '--format' in argv:
            try:
                format_file(root / 'route_links.json')
            except ValueError as error:
                problems.append(f'{root / "route_links.json"} {error}')
                continue
        problems.extend(check_package(name, root, owned, served))

    if problems:
        print('\n'.join(problems))
        print(f'\nroute_links.json is out of date with the routes. {FIX}')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
