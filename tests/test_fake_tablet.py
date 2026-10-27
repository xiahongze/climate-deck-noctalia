import copy
import importlib.util
import pathlib

path = pathlib.Path(__file__).with_name("fake_tablet.py")
spec = importlib.util.spec_from_file_location("fake_tablet", path)
fake = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fake)
state = {"aircons": {"ac1": {"info": {"name": "Home"}, "zones": {"z01": {"name": "Room"}}}},
         "myScenes": {"scenes": {"s10001": {"id": "s10001", "name": "Old", "lights": {"kitchen": "on"}, "aircons": {"ac1": {"old": True}}}}, "scenesOrder": ["s10001"]}}
assert fake.apply_command(state, "/setAircon", {"ac1": {"zones": {"z01": {"name": "Study"}}}})["ack"]
assert state["aircons"]["ac1"]["zones"]["z01"]["name"] == "Study"
assert fake.apply_command(state, "/setAircon", {"ac1": {"info": {"myAutoHeatTargetTemp": 20, "myAutoCoolTargetTemp": 24}}})["ack"]
assert state["aircons"]["ac1"]["info"]["myAutoCoolTargetTemp"] == 24
assert fake.apply_command(state, "/setScene", {"id": "s10001", "name": "New", "aircons": {"ac1": {"new": True}}})["ack"]
scene = state["myScenes"]["scenes"]["s10001"]
assert scene["lights"] == {"kitchen": "on"} and scene["aircons"] == {"ac1": {"new": True}}
for n in range(2, 13):
    assert fake.apply_command(state, "/setScene", {"id": f"s1{n:04}", "name": f"Scene {n}"})["ack"]
before = copy.deepcopy(state)
assert fake.apply_command(state, "/setScene", {"id": "s10013", "name": "Too many"})["ack"]
assert state == before
print("fake tablet behavior: ok")
