import {
  ButtonItem,
  PanelSection,
  PanelSectionRow,
  ToggleField,
  staticClasses,
} from "@decky/ui";
import { callable, definePlugin, toaster } from "@decky/api";
import { useEffect, useState } from "react";
import { FaMoon } from "react-icons/fa";

// Mirrors Plugin.get_status in main.py.
type Status = {
  restEnabled: boolean;
  autoRestMinutes: number;
  autoRest: boolean;
  shutdownWhenDone: boolean;
  boost: boolean | null; // null when boost isn't managed by game mode
  updatePending: boolean; // an update changed the kernel
};

const getStatus = callable<[], Status>("get_status");
const setSetting = callable<[name: string, on: boolean], void>("set_setting");
const setBoost = callable<[on: boolean], boolean>("set_boost");
const restNow = callable<[], boolean>("rest_now");
const finishUpdate = callable<[], boolean>("finish_update");
const reportDownloads = callable<[pending: number], void>("report_downloads");

// Tells rest mode how many Steam downloads are still to do, so it doesn't
// shut down while Steam waits on a download schedule or a slow server. An
// item paused by hand doesn't count: it would keep the console up forever.
function watchDownloads() {
  let last = -1;
  return SteamClient.Downloads.RegisterForDownloadItems((isDownloading, items) => {
    const pending = items.filter((i) => !i.completed && !i.paused).length;
    const count = isDownloading ? Math.max(pending, 1) : pending;
    if (count !== last) {
      last = count;
      reportDownloads(count);
    }
  });
}

function Content() {
  const [status, setStatus] = useState<Status | null>(null);
  const refresh = () => getStatus().then(setStatus);
  useEffect(() => {
    refresh();
  }, []);

  if (!status) return null;

  const toggle = (name: string) => async (on: boolean) => {
    await setSetting(name, on);
    await refresh();
  };

  return (
    <>
      {status.updatePending && (
        <PanelSection title="Update">
          <PanelSectionRow>
            <ButtonItem
              layout="below"
              description="Starts the new kernel in a few seconds and comes back to game mode. Closes the running game."
              onClick={async () => {
                if (!(await finishUpdate())) {
                  toaster.toast({ title: "Alloy", body: "Couldn't restart; reboot to finish the update" });
                }
              }}
            >
              Restart to finish update
            </ButtonItem>
          </PanelSectionRow>
        </PanelSection>
      )}
      {status.restEnabled && (
        <PanelSection title="Rest mode">
          <PanelSectionRow>
            <ButtonItem
              layout="below"
              description="Screen off, downloads keep going. Press PS to wake. Closes the running game."
              onClick={async () => {
                if (!(await restNow())) {
                  toaster.toast({ title: "Alloy", body: "Couldn't start rest mode" });
                }
              }}
            >
              Rest now
            </ButtonItem>
          </PanelSectionRow>
          <PanelSectionRow>
            <ToggleField
              label="Shut down when downloads finish"
              checked={status.shutdownWhenDone}
              onChange={toggle("shutdown-when-done")}
            />
          </PanelSectionRow>
          {status.autoRestMinutes > 0 && (
            <PanelSectionRow>
              <ToggleField
                label={`Rest after ${status.autoRestMinutes} min idle`}
                description="Never while a game is running"
                checked={status.autoRest}
                onChange={toggle("auto-rest")}
              />
            </PanelSectionRow>
          )}
        </PanelSection>
      )}
      {status.boost !== null && (
        <PanelSection title="Performance">
          <PanelSectionRow>
            <ToggleField
              label="Boost"
              description="CPU 3.5 GHz, GPU 2.23 GHz. Back on next time game mode starts."
              checked={status.boost}
              onChange={async (on) => {
                await setBoost(on);
                await refresh();
              }}
            />
          </PanelSectionRow>
        </PanelSection>
      )}
    </>
  );
}

export default definePlugin(() => {
  const downloads = watchDownloads();
  return {
    name: "Alloy",
    titleView: <div className={staticClasses.Title}>Alloy</div>,
    content: <Content />,
    icon: <FaMoon />,
    onDismount: () => downloads.unregister(),
  };
});
