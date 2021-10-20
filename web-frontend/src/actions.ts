import { LayerDescription, baseLayers } from "./map/style";

export interface MapState {
  enableGeology: boolean;
  activeLayer: LayerDescription;
  activeSpots: Object[] | null;
}

type SetActiveLayer = { type: "set-active-layer"; layer: LayerDescription };
type ToggleGeology = { type: "toggle-geology" };
type SetActiveSpot = { type: "set-active-spots"; spots: Object[] | null };

export type MapAction = SetActiveLayer | ToggleGeology | SetActiveSpot;

export const defaultState: MapState = {
  enableGeology: true,
  activeLayer: baseLayers[0],
  activeSpots: null,
};

export function mapReducer(state: MapState, action: MapAction) {
  switch (action.type) {
    case "set-active-layer":
      return { ...state, activeLayer: action.layer };
    case "toggle-geology":
      return { ...state, enableGeology: !state.enableGeology };
    case "set-active-spots":
      return { ...state, activeSpots: action.spots };
    default:
      return state;
  }
}
