async function loadImage(map, url: string) {
  return new Promise((resolve, reject) => {
    map.loadImage(url, function (err, image) {
      // Throw an error if something went wrong
      if (err) {
        console.error(`Could not load image ${url}`);
        reject(err);
      }
      // Declare the image
      resolve(image);
    });
  });
}

export { loadImage };
