import "babel-polyfill";
import h from "@macrostrat/hyper";
import { render } from "react-dom";
import { FocusStyleManager } from "@blueprintjs/core";

import { MapApp } from "./app";
import "@blueprintjs/core/lib/css/blueprint.css";
import "@macrostrat/ui-components/lib/esm/index.css";
import "./main.styl";

FocusStyleManager.onlyShowFocusOnTabs();

render(h(MapApp), document.getElementById("app"));
