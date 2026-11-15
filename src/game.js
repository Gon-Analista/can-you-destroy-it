// Can you destroy it? — punto de partida
const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d');

function draw() {
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.fillStyle = '#eee';
  ctx.font = '20px system-ui';
  ctx.textAlign = 'center';
  ctx.fillText('Próximamente...', canvas.width / 2, canvas.height / 2);
  requestAnimationFrame(draw);
}

draw();
