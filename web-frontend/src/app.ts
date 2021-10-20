import { useReducer } from "react";
import h from "@macrostrat/hyper";
import { Button, ButtonGroup, Switch, Icon } from "@blueprintjs/core";
import "@blueprintjs/core/lib/css/blueprint.css";
import "@blueprintjs/popover2/lib/css/blueprint-popover2.css";
import { Popover2 } from "@blueprintjs/popover2";
import { ModalPanel } from "@macrostrat/ui-components";
import { BaseLayerSwitcher } from "./layer-switcher";
import { Spot } from "./spots";
import { mapReducer, defaultState } from "./actions";
import { MapComponent } from "./map";

function InfoModal({ isOpen, onClose, spots = [] }) {
  if (!isOpen) return null;

  return h(
    ModalPanel,
    {
      title: "Spots",
      onClose,
    },
    spots.map((spot) => {
      return h(Spot, { data: spot.properties });
    })
  );
}

export function MapApp() {
  const [state, dispatch] = useReducer(mapReducer, defaultState);

  const isOpen = state.activeSpots != null;

  return h("div.map-area", [
    h(MapComponent, { state, dispatch }),
    h("div.map-controls", null, [
      h(ButtonGroup, { vertical: true }, [
        //h(Popover2, { content: "Toggle" }, [
        h(
          Button,
          {
            active: state.enableSpots,
            onClick() {
              dispatch({ type: "toggle-spots" });
            },
          },
          "Spots"
        ),
        ///]),
        h(
          Button,
          {
            active: state.enableGeology,
            onClick() {
              dispatch({ type: "toggle-geology" });
            },
          },
          "Geology"
        ),
      ]),
      h(Switch, {
        checked: state.showAllSpots,
        label: "Show all spots",
        onChange: () => dispatch({ type: "toggle-all-spots" }),
      }),

      h(BaseLayerSwitcher, {
        activeLayer: state.activeLayer,
        onSetLayer(layer) {
          dispatch({ type: "set-active-layer", layer });
        },
      }),
    ]),
    h("div.map-info", [
      h(InfoModal, {
        isOpen,
        onClose() {
          dispatch({ type: "set-active-spots", spots: null });
        },
        spots: state.activeSpots,
      }),
    ]),
  ]);
}
