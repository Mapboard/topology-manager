import h from "@macrostrat/hyper";
import { ButtonGroup, Button } from "@blueprintjs/core";
import { terrain } from "./map-style";

export interface LayerDescription {
  id: string;
  name: string;
  url: string;
}

export const baseLayers: LayerDescription[] = [
  {
    id: "satellite",
    name: "Satellite",
    url: "mapbox://styles/mapbox/satellite-v9",
  },
  {
    id: "hillshade",
    name: "Hillshade",
    url: terrain,
  },
];

export function BaseLayerSwitcher({
  activeLayer,
  onSetLayer,
  layers = baseLayers,
}: {
  activeLayer: LayerDescription;
  onSetLayer: Function;
  layers?: LayerDescription[];
}) {
  return h(
    ButtonGroup,
    { vertical: true },
    layers.map((d) => {
      return h(
        Button,
        {
          active: d == activeLayer,
          //disabled: d == activeLayer,
          onClick() {
            if (d == activeLayer) return;
            onSetLayer(d);
          },
        },
        d.name
      );
    })
  );
}
