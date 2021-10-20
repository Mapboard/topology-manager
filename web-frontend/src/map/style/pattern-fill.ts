interface PatternFillSpec {
  color: string;
  patternURL?: string;
  patternColor?: string;
}

function loadImage(url): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.crossOrigin = "anonymous";
    img.addEventListener("load", () => resolve(img));
    img.addEventListener("error", (err) => reject(err));
    img.src = url;
  });
}

function recolorPatternImage(
  img: HTMLImageElement,
  backgroundColor: string,
  color: string
) {
  // create hidden canvas
  var canvas = document.createElement("canvas");
  canvas.width = img.width;
  canvas.height = img.height;

  var ctx = canvas.getContext("2d");
  ctx.drawImage(img, 0, 0, img.width, img.height);

  //ctx.fillStyle = imgColor;
  //ctx.fillRect(0, 0, 40, 40);

  // overlay using source-atop to follow transparency
  ctx.globalCompositeOperation = "source-in";
  //ctx.globalAlpha = 0.3;
  ctx.globalAlpha = 0.8;
  ctx.fillStyle = color;
  ctx.fillRect(0, 0, img.width, img.height);

  ctx.globalCompositeOperation = "destination-over";

  //const map = ctx.getImageData(0, 0, img.width, img.height);

  ctx.globalAlpha = 0.5;
  ctx.fillStyle = backgroundColor;
  ctx.fillRect(0, 0, img.width, img.height);

  //ctx.putImageData(map, 0, 0);

  // replace image source with canvas data
  return ctx.getImageData(0, 0, img.width, img.height);
}

function createSolidColorImage(imgColor) {
  var canvas = document.createElement("canvas");
  var ctx = canvas.getContext("2d");
  canvas.width = 40;
  canvas.height = 40;
  ctx.globalAlpha = 0.5;
  ctx.fillStyle = imgColor;
  ctx.fillRect(0, 0, 40, 40);
  return ctx.getImageData(0, 0, 40, 40);
}

async function createUnitFill(spec: PatternFillSpec): Promise<ImageData> {
  /** Create a fill image for a map unit. */
  if (spec.patternURL != null) {
    const img = await loadImage(spec.patternURL);
    return recolorPatternImage(img, spec.color, spec.patternColor ?? "#000000");
  } else {
    return createSolidColorImage(spec.color);
  }
}

export { recolorPatternImage, createUnitFill };
