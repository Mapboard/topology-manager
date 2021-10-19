import h from "@macrostrat/hyper";
import { render } from "react-dom";
import { MapComponent } from "./map";
import "@blueprintjs/core/lib/css/blueprint.css";
import "@macrostrat/ui-components/lib/esm/index.css";
import "./main.styl";
import { FocusStyleManager } from "@blueprintjs/core";

FocusStyleManager.onlyShowFocusOnTabs();

function App() {
  return h(MapComponent);
}

const el = document.getElementById("app");
render(h(App), el);
