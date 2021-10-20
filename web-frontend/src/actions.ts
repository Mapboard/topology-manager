import { LayerDescription, baseLayers } from "./map/style";

export interface MapState {
  enableGeology: boolean;
  enableSpots: boolean;
  showAllSpots: boolean;
  activeLayer: LayerDescription;
  activeSpots: Object[] | null;
}

type SetActiveLayer = { type: "set-active-layer"; layer: LayerDescription };
type ToggleGeology = { type: "toggle-geology" };
type ToggleSpots = { type: "toggle-spots" };
type ToggleAllSpots = { type: "toggle-all-spots" };
type SetActiveSpot = { type: "set-active-spots"; spots: Object[] | null };

export type MapAction =
  | SetActiveLayer
  | ToggleGeology
  | ToggleSpots
  | ToggleAllSpots
  | SetActiveSpot;

export const defaultState: MapState = {
  enableGeology: true,
  enableSpots: true,
  showAllSpots: false,
  activeLayer: baseLayers[0],
  activeSpots: null,
};

export function mapReducer(state: MapState, action: MapAction) {
  switch (action.type) {
    case "set-active-layer":
      return { ...state, activeLayer: action.layer };
    case "toggle-geology":
      return { ...state, enableGeology: !state.enableGeology };
    case "toggle-spots":
      return { ...state, enableSpots: !state.enableSpots };
    case "toggle-all-spots":
      return { ...state, showAllSpots: !state.showAllSpots };
    case "set-active-spots":
      return { ...state, activeSpots: action.spots };
    default:
      return state;
  }
}
