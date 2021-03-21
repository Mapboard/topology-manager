import h from "@macrostrat/hyper";
import { render } from "react-dom";
import { Map } from "./map";
import "./main.styl";

function App() {
  return h(Map);
}

const el = document.getElementById("app");
render(h(App), el);
