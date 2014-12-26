/* dropzone.js
 *
 * Code for a drag-and-drop image input and resize
 * to be used with the templates/profile.html page.
 */
var dropbox;
dropbox = document.getElementById("image_drop_zone");
dropbox.addEventListener("dragenter", dragenter, false);
dropbox.addEventListener("dragover", dragover, false);
dropbox.addEventListener("dragleave", dragleave, false);
dropbox.addEventListener("drop", drop, false);

var form;
var addImage = function() { return false;};
form = document.forms.namedItem("input_form");
form.addEventListener("submit", addImage, false);

function dragenter(e) {
  e.stopPropagation();
  e.preventDefault();
  this.classList.add('over');
}

function dragleave(e) {
  this.classList.remove('over');
}

function dragover(e) {
  e.stopPropagation();
  e.preventDefault();
}

function drop(e) {
  e.stopPropagation();
  e.preventDefault();

  var dt = e.dataTransfer;
  var f = dt.files[0];
  handleFile(f);
}

function handleFile(f) {
  if (f) {
    var imageType = /image.*/;

    if (! f.type.match(imageType)) {
      alert("Eeep. Browser doesn't recognize this as an image..");
      return(false);
    }

    var img = document.getElementById("avatar");
    img.file = f;

    var reader = new FileReader();
    reader.onload = (function(aImg) { return function(e) {
        var tmp_img = new Image();
        tmp_img.src = e.target.result;
        aImg.src = ImageTools.scaleImage(tmp_img); 
    }; })(img);
    reader.readAsDataURL(f);


    addImage = function(e) {
      formData = new FormData(form);

      formData.append(
          "image",
          dataURItoBlob(document.getElementById("avatar").src),
          "image.jpg");
      var xhr = new XMLHttpRequest();
      xhr.open('POST', form.getAttribute('action'), true);
      xhr.send(formData);
      setTimeout(function() { window.location.reload(true); }, 10);
      return false; 
    };
    form.addEventListener("submit", addImage, false);
  }
}


/* Image to file blob:
 *  http://stackoverflow.com/questions/4998908/convert-data-uri-to-file-then-append-to-formdata
 */
function dataURItoBlob(dataURI) {
    var byteString = atob(dataURI.split(',')[1]);
    var ab = new ArrayBuffer(byteString.length);
    var ia = new Uint8Array(ab);
    for (var i = 0; i < byteString.length; i++) {
        ia[i] = byteString.charCodeAt(i);
    }
    return new Blob([ab], { type: 'image/jpeg' });
}

/* Image resize:
 *  http://stackoverflow.com/questions/10333971/html5-pre-resize-images-before-uploading
 */
var ImageTools = {};
ImageTools.config = { 'maxWidth': 100, 'quality': 0.88};

ImageTools.scaleImage = function(img) {
    var canvas = document.createElement('canvas');
    var smallerDim = Math.min(img.naturalWidth, img.naturalHeight);
    canvas.width = smallerDim;
    canvas.height = smallerDim;

    // delta above square
    var dx = (img.naturalWidth - smallerDim) / 2;
    var dy = (img.naturalHeight - smallerDim) / 2;
    canvas.getContext('2d').drawImage(img,
        0+dx, 0+dy, smallerDim, smallerDim,
        0, 0, smallerDim, smallerDim);

    while (canvas.width >= (2 * this.config.maxWidth)) {
        canvas = this.getHalfScaleCanvas(canvas);
    }

    if (canvas.width > this.config.maxWidth) {
        canvas = this.scaleCanvasWithAlgorithm(canvas);
    }

    var imageData = canvas.toDataURL('image/jpeg', this.config.quality);
    // return dataURItoBlob(imageData);
    return (imageData);
};

ImageTools.scaleCanvasWithAlgorithm = function(canvas) {
    var scaledCanvas = document.createElement('canvas');

    var scale = this.config.maxWidth / canvas.width;

    scaledCanvas.width = canvas.width * scale;
    scaledCanvas.height = canvas.height * scale;

    var srcImgData = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height);
    var destImgData = scaledCanvas.getContext('2d').createImageData(scaledCanvas.width, scaledCanvas.height);

    this.applyBilinearInterpolation(srcImgData, destImgData, scale);

    scaledCanvas.getContext('2d').putImageData(destImgData, 0, 0);

    return scaledCanvas;
};

ImageTools.getHalfScaleCanvas = function(canvas) {
    var halfCanvas = document.createElement('canvas');
    halfCanvas.width = canvas.width / 2;
    halfCanvas.height = canvas.height / 2;

    halfCanvas.getContext('2d').drawImage(canvas, 0, 0, halfCanvas.width, halfCanvas.height);

    return halfCanvas;
};

ImageTools.applyBilinearInterpolation = function(srcCanvasData, destCanvasData, scale) {
    function inner(f00, f10, f01, f11, x, y) {
        var un_x = 1.0 - x;
        var un_y = 1.0 - y;
        return (f00 * un_x * un_y + f10 * x * un_y + f01 * un_x * y + f11 * x * y);
    }
    var i, j;
    var iyv, iy0, iy1, ixv, ix0, ix1;
    var idxD, idxS00, idxS10, idxS01, idxS11;
    var dx, dy;
    var r, g, b, a;
    for (i = 0; i < destCanvasData.height; ++i) {
        iyv = i / scale;
        iy0 = Math.floor(iyv);
        // Math.ceil can go over bounds
        iy1 = (Math.ceil(iyv) > (srcCanvasData.height - 1) ? (srcCanvasData.height - 1) : Math.ceil(iyv));
        for (j = 0; j < destCanvasData.width; ++j) {
            ixv = j / scale;
            ix0 = Math.floor(ixv);
            // Math.ceil can go over bounds
            ix1 = (Math.ceil(ixv) > (srcCanvasData.width - 1) ? (srcCanvasData.width - 1) : Math.ceil(ixv));
            idxD = (j + destCanvasData.width * i) * 4;
            // matrix to vector indices
            idxS00 = (ix0 + srcCanvasData.width * iy0) * 4;
            idxS10 = (ix1 + srcCanvasData.width * iy0) * 4;
            idxS01 = (ix0 + srcCanvasData.width * iy1) * 4;
            idxS11 = (ix1 + srcCanvasData.width * iy1) * 4;
            // overall coordinates to unit square
            dx = ixv - ix0;
            dy = iyv - iy0;
            // I let the r, g, b, a on purpose for debugging
            r = inner(srcCanvasData.data[idxS00], srcCanvasData.data[idxS10], srcCanvasData.data[idxS01], srcCanvasData.data[idxS11], dx, dy);
            destCanvasData.data[idxD] = r;

            g = inner(srcCanvasData.data[idxS00 + 1], srcCanvasData.data[idxS10 + 1], srcCanvasData.data[idxS01 + 1], srcCanvasData.data[idxS11 + 1], dx, dy);
            destCanvasData.data[idxD + 1] = g;

            b = inner(srcCanvasData.data[idxS00 + 2], srcCanvasData.data[idxS10 + 2], srcCanvasData.data[idxS01 + 2], srcCanvasData.data[idxS11 + 2], dx, dy);
            destCanvasData.data[idxD + 2] = b;

            a = inner(srcCanvasData.data[idxS00 + 3], srcCanvasData.data[idxS10 + 3], srcCanvasData.data[idxS01 + 3], srcCanvasData.data[idxS11 + 3], dx, dy);
            destCanvasData.data[idxD + 3] = a;
        }
    }
};
