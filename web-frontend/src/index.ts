import h from "@macrostrat/hyper";
import { render } from "react-dom";
import { MapComponent } from "./map";
import "./main.styl";
import { FocusStyleManager } from "@blueprintjs/core";

FocusStyleManager.onlyShowFocusOnTabs();

function App() {
  return h(MapComponent);
}

const el = document.getElementById("app");
render(h(App), el);
