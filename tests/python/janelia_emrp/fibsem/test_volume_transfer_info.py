import json
from datetime import datetime
from pathlib import Path

from janelia_emrp.fibsem.volume_transfer_info import VolumeTransferInfo, RenderConnect


def test_json():

    volume_transfer_info = VolumeTransferInfo(
        scope="jeiss2.hhmi.org",
        scope_storage_root=Path("/cygdrive/e/Images/Renel Cell Carcinoma"),
        dat_storage_roots=[Path("/nearline/flyem2/data/NIH-J1/dat")],
        dat_x_and_y_nm_per_pixel=8,
        dat_z_nm_per_pixel=8,
        acquire_start=datetime.strptime("22-03-08_223009", "%y-%m-%d_%H%M%S"),
        acquire_stop=datetime.strptime("22-03-17_082104", "%y-%m-%d_%H%M%S"),
        archive_storage_root=Path("/nearline/flyem2/data/NIH-J1/h5"),
        remove_dat_after_archive=False,
        align_storage_root=Path("/nrs/flyem/render/data/test_h5/NIH_J1"),
        align_mask_mipmap_root=Path("/nrs/flyem/render/mipmaps"),
        max_mipmap_level=7,
        render_owner="test_h5",
        render_project="NIH_J1",
        render_connect=RenderConnect(host="renderer-dev.int.janelia.org",
                                     port=8080,
                                     web_only=True,
                                     validate_client=False,
                                     client_scripts="/groups/flyTEM/flyTEM/render/bin",
                                     memGB="1G")
    )

    json_string = volume_transfer_info.json()

    debug_json_object = json.loads(json_string)
    print(f"\nencoded {volume_transfer_info} as:")
    print(json.dumps(debug_json_object, indent=True))

    parsed_info = VolumeTransferInfo.parse_raw(json_string)

    assert volume_transfer_info == parsed_info, "source and parsed data differ"
