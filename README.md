# airpods-connect: one-click AirPods for Windows

**Get your AirPods back from your iPhone with one click.**

Apple's automatic switching only moves AirPods between Apple devices. On Windows, taking them back means opening Bluetooth settings, finding the device and clicking Connect, and that sometimes fails. This adds a **Connect AirPods** shortcut that does it in one click, in about three seconds.

- Tested with AirPods Max on a Surface Pro 9 running Windows 11. It uses the same Windows request for every Bluetooth headset, so other AirPods, Beats and other headphones should work too; use `-Name` for non-AirPods.
- No admin rights, nothing to install beyond one PowerShell script, and **no network connections**.
- It runs in Windows PowerShell 5.1, which comes with Windows 10 and 11.

## Quick start

```powershell
irm https://raw.githubusercontent.com/jacobrakaiFoundation/airpods-connect/main/Install.ps1 | iex
```

Or download the repository and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1
```

Pair your AirPods in **Settings → Bluetooth & devices** first. After that, click **Connect AirPods** on the Desktop or in the Start menu whenever you want them on the PC. A notification tells you whether they connected. To get a taskbar button, right-click the Start menu entry and choose **Pin to taskbar**.

Install options:

- **Other headphones:** `Install.ps1 -Name "WH-1000XM5"` makes the shortcut connect any paired device whose name contains that text.
- **Start menu only:** `Install.ps1 -NoDesktop`.
- **Remove:** `Install.ps1 -Uninstall` deletes the script and both shortcuts.

## Using the script directly

```powershell
.\Connect-AirPods.ps1                  # connect anything named *AirPods*
.\Connect-AirPods.ps1 -Disconnect      # disconnect audio
.\Connect-AirPods.ps1 -Name "Sony"     # another headset
.\Connect-AirPods.ps1 -Quiet           # print the result instead of a notification
```

The exit status is `0` when the headphones end up connected (or disconnected with `-Disconnect`) and `1` when they don't.

After `-Disconnect`, AirPods reconnect to the PC on their own after about 12 seconds unless another device takes them.

## Stop your iPhone taking them back

When Apple's switching is set to Automatically, your iPhone or Mac can take the AirPods back from Windows when a notification arrives. On each Apple device, with the AirPods connected, go to **Settings → Bluetooth → ⓘ next to the AirPods → Connect to This iPhone** and choose **When Last Connected to This iPhone**. On a Mac the same setting is in **System Settings → (your AirPods)**.

## How it works

Windows' Bluetooth audio drivers support two requests, `KSPROPERTY_ONESHOT_RECONNECT` and `KSPROPERTY_ONESHOT_DISCONNECT`. These are the requests Settings makes when you click Connect. The script finds the paired device's audio endpoints, follows each one to the driver behind it, and sends the request there. [ToothTray](https://github.com/m2jean/ToothTray) uses the same approach.

Some PCs use **Intel Smart Sound Technology** Bluetooth offload instead of Microsoft's Bluetooth audio driver; many Surface and recent Intel laptops do. Intel's driver rejects both requests on the stereo "Headphones" endpoint, but accepts them on the "Hands-Free" endpoint, even while that endpoint shows as not present. Reconnecting through Hands-Free brings full stereo audio back in under a second. The script tries every endpoint in turn, so it works with either driver.

The first run compiles a small helper DLL (`AirPodsConnect.dll`) next to the script, and later runs reuse it. It is rebuilt automatically if the script changes.

## Limits

- The AirPods have to be paired with the PC and in range. AirPods Max must be out of the Smart Case, and AirPods out of the charging case.
- Windows gets the same audio as with any other connection: AAC or SBC for stereo, and lower-quality mono while an app uses the AirPods microphone.
- This does not add Apple-style automatic switching to Windows. It makes switching back a single click.

## License

MIT. See [LICENSE](LICENSE).
