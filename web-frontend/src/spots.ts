import h from "@macrostrat/hyper";
import { JSONView } from "@macrostrat/ui-components";

type SpotData = object;

export function Spot(props: { data: SpotData }) {
  let { data } = props;
  for (const [key, value] of Object.entries(data)) {
    try {
      data[key] = JSON.parse(value);
    } catch (e) {
      continue;
    }
  }

  return h(JSONView, { data });
}
