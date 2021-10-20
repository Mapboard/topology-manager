import h from "@macrostrat/hyper";
import { ButtonGroup, Button } from "@blueprintjs/core";
import { baseLayers, LayerDescription } from "./map/style";

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
