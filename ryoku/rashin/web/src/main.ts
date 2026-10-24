import { mount } from "svelte";
import "./app.css";
import "$lib/ui/kit.css";
import App from "./App.svelte";

export default mount(App, { target: document.getElementById("app")! });
