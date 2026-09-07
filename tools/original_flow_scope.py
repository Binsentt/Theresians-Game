"""Prove/commit only this restoration's hunks, retaining the prior dirty index."""
import base64
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(r"C:\Users\vince\Documents\Capstone-Project\capstone-theresians-quest")
QA = ROOT / "docs/qa"
BASELINE = QA / "2026-09-07-original-flow-progress-baseline.json"
BUNDLE = QA / "2026-09-07-original-flow-commit-bundle.json"
PRODUCT = ["Battle/Battle-Enemy/QuizManager.gd", "scripts/remote_sync.gd", "scenes/oak_leaf_village.tscn"]
ADDED = [
    "tools/original_battle_presentation_test.gd", "tools/original_battle_presentation_test.tscn",
    "tools/original_flow_ingestion_test.gd", "tools/original_flow_ingestion_test.tscn",
    "tools/original_interaction_regression_test.gd", "tools/original_interaction_regression_test.tscn",
    "tools/original_flow_scope.py", "docs/qa/2026-09-07-original-quest-flow-audit.md",
    "docs/qa/2026-09-07-original-battle-audit.md",
    "docs/qa/2026-09-07-original-gameplay-repair-evidence.md",
]
EFFECT = '''\t# Keep the original final hit and result visible until the existing effect
\t# finishes; the quest owner frees this scene when battle_finished is emitted.
\tvar terminal_effect: Node2D = enemy_effect if success else player_effect
\tvar animation := terminal_effect.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
\tif animation != null and animation.is_playing():
\t\tawait animation.animation_finished
'''
OLD_EVENT = 'previous_index if event_type == "task_completed" else current_index'
NEW_EVENT = 'previous_index if event_type in ["task_completed", "quest_completed"] else current_index'
EXIT = '[connection signal="body_exited" from="NPC1/Area2D" to="NPC1/InteractableArea" method="_on_body_exited"]\n'
EDITABLE = '\n[editable path="girl_npc"]\n[editable path="villager-female"]\n'


def git(*args, data=None, env=None):
    return subprocess.run(["git", *args], cwd=ROOT, input=data, env=env,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout


def digest(content):
    return hashlib.sha256(content).hexdigest()


def once(text, old, new):
    assert text.count(old) == 1, ("Expected exactly one occurrence", old[:100])
    return text.replace(old, new, 1)


def focused(path, data):
    """Apply reviewed changes to HEAD or pre-existing index bytes only."""
    text = data.decode()
    if path == PRODUCT[0]:
        text = once(text, '\tdisable_buttons()\n\tbattle_finished.emit(success)',
                    '\tdisable_buttons()\n' + EFFECT + '\tbattle_finished.emit(success)')
    elif path == PRODUCT[1]:
        text = once(text, OLD_EVENT, NEW_EVENT)
    else:
        assert text.count('editable_children = true\n') == 2
        text = text.replace('editable_children = true\n', '')
        for actor in ['girl_npc', 'villager-female']:
            text = once(text, f'[node name="Visual" parent="{actor}" index=0]',
                        f'[node name="Visual" parent="{actor}" index="0"]')
        assert EXIT not in text
        text += EXIT + EDITABLE
    return text.encode()


def index_entries():
    return {entry.split(b'\t', 1)[1].decode(): entry.split(b'\t', 1)[0].decode()
            for entry in git('ls-files', '--stage', '-z').split(b'\0') if entry}


def verify():
    baseline = json.loads(BASELINE.read_text())[str(ROOT)]
    changed = []
    for path, original_hash in baseline['files'].items():
        file = ROOT / path
        current_hash = digest(file.read_bytes()) if file.exists() else None
        if current_hash != original_hash:
            changed.append(path)
    assert sorted(changed) == sorted(PRODUCT), changed
    # Reversing only the authorized lines must recover the captured starting
    # bytes. This proves all other tracked source (including dirty work) intact.
    quiz = (ROOT / PRODUCT[0]).read_bytes()
    assert digest(once(quiz.decode(), EFFECT, '').encode()) == baseline['files'][PRODUCT[0]]
    sync = (ROOT / PRODUCT[1]).read_bytes()
    assert digest(once(sync.decode(), NEW_EVENT, OLD_EVENT).encode()) == baseline['files'][PRODUCT[1]]
    oak = (ROOT / PRODUCT[2]).read_text()
    for actor in ['girl_npc', 'villager-female']:
        block = (f'[node name="Visual" parent="{actor}" index="0"]\n'
                 'script = ExtResource("22_0r4je")\n'
                 'quest_ui_path = NodePath("../../CanvasLayer/Panel")\n\n')
        oak = once(oak, block, '')
    oak = once(once(oak, EXIT, ''), EDITABLE, '')
    before = (QA / '2026-09-07-original-interaction-oakleaf-before.txt').read_bytes()
    assert digest(before) == baseline['files'][PRODUCT[2]]
    assert oak == before.decode().replace('\r\n', '\n'), 'Unrelated Oakleaf scene change'
    result = {'starting_head': baseline['head'], 'changed_product_paths': PRODUCT,
              'unchanged_tracked_files': len(baseline['files']) - len(PRODUCT),
              'unrelated_product_delta_count': 0,
              'oakleaf_only_two_visual_script_bindings_exit_connection_and_editable_metadata': True,
              'map_background_hud_teacher_triggers_dialogue_controls_unchanged': True}
    (QA / '2026-09-07-original-flow-preservation-proof.json').write_text(json.dumps(result, indent=2))
    return result


def prepare():
    proof = verify()
    assert git('rev-parse', 'HEAD').decode().strip() == proof['starting_head']
    index = index_entries()
    files = {}
    for path in PRODUCT:
        files[path] = {'mode': index[path].split()[0],
                       'content': base64.b64encode(focused(path, git('show', 'HEAD:' + path))).decode(),
                       'index_content': base64.b64encode(focused(path, git('show', ':' + path))).decode()}
    for path in ADDED:
        assert path not in index
        files[path] = {'mode': '100644', 'content': base64.b64encode((ROOT / path).read_bytes().replace(b'\r\n', b'\n')).decode()}
    bundle = {'head': proof['starting_head'], 'index_before': index, 'files': files}
    BUNDLE.write_text(json.dumps(bundle, indent=2))
    print(json.dumps({'prepared_paths': sorted(files), 'proof': proof}))


def commit():
    bundle = json.loads(BUNDLE.read_text())
    verify()
    assert git('rev-parse', 'HEAD').decode().strip() == bundle['head']
    assert index_entries() == bundle['index_before'], 'Concurrent index change'
    temp = Path(tempfile.mkdtemp(prefix='original-flow-index-'))
    env = dict(os.environ, GIT_INDEX_FILE=str(temp / 'index'))
    git('read-tree', bundle['head'], env=env)
    for path, entry in bundle['files'].items():
        oid = git('hash-object', '-w', '--stdin', data=base64.b64decode(entry['content'])).decode().strip()
        git('update-index', '--add', '--cacheinfo', entry['mode'], oid, path, env=env)
    git('diff', '--cached', '--check', env=env)
    names = git('diff', '--cached', '--name-only', '-z', env=env).decode().strip('\0').split('\0')
    assert sorted(names) == sorted(bundle['files'])
    print(git('diff', '--cached', '--stat', env=env).decode())
    print(git('commit', '-m', 'Preserve original battle effects and canonical interaction events', env=env).decode())
    # Preserve the original staged statistics hunk as staged; do not replace it
    # with the clean commit blob or accidentally include it in this commit.
    for path, entry in bundle['files'].items():
        content = base64.b64decode(entry.get('index_content', entry['content']))
        oid = git('hash-object', '-w', '--stdin', data=content).decode().strip()
        git('update-index', '--add', '--cacheinfo', entry['mode'], oid, path)
    after = index_entries()
    untouched_before = {p: v for p, v in bundle['index_before'].items() if p not in bundle['files']}
    untouched_after = {p: v for p, v in after.items() if p not in bundle['files']}
    assert untouched_after == untouched_before
    result = {'head': git('rev-parse', 'HEAD').decode().strip(), 'parent': bundle['head'],
              'committed_paths': names, 'unrelated_index_delta_count': 0,
              'preexisting_quiz_statistics_remain_staged': True}
    (QA / '2026-09-07-original-flow-commit-result.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result))


if __name__ == '__main__':
    assert Path.cwd().resolve() == ROOT.resolve()
    if sys.argv[1] == 'verify':
        print(json.dumps(verify()))
    else:
        {'prepare': prepare, 'commit': commit}[sys.argv[1]]()
