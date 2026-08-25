extends Node

var profile_request_count := 0
var requested_student_ids: Array[String] = []


func request_get(path: String, _params: Dictionary = {}, _timeout_ms: int = -1) -> Dictionary:
	profile_request_count += 1
	var student_id := path.get_file()
	requested_student_ids.append(student_id)
	if student_id == "000001" or student_id == "000002":
		return {
			"ok": true,
			"status": 200,
			"body": {
				"ok": true,
				"can_play": true,
				"should_block": false,
				"canonical_profile": {
					"name": "Child One" if student_id == "000001" else "Child Two",
					"grade_level": "Grade 1",
					"section": null,
				},
			},
		}
	if student_id == "000003":
		return {
			"ok": false,
			"status": 403,
			"body": {"error": "This Student is not linked to this Parent account."},
		}
	if student_id == "000004":
		return {
			"ok": false,
			"status": 404,
			"body": {"error": "Student ID does not exist."},
		}
	return {
		"ok": false,
		"status": 404,
		"body": {"error": "Parent ID does not exist."},
	}
