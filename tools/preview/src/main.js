import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import ELEMENTS from '../data/elements.json';
import './styles.css';

const $ = (selector) => document.querySelector(selector);
const PROFILE_ORDER = ['body', 'char', 'crush', 'melt', 'brittle', 'dissolve', 'gib', 'destroy'];
const PROFILE_LABELS = {
  body: 'ОБЫЧНОЕ ТЕЛО',
  char: 'ОБУГЛИВАЕТСЯ',
  crush: 'РАЗДАВЛИВАЕТСЯ',
  melt: 'ПЛАВИТСЯ',
  brittle: 'ХРУПКИЙ ТРУП',
  dissolve: 'РАСТВОРЯЕТСЯ',
  gib: 'РАЗРЫВАЕТСЯ',
  destroy: 'УНИЧТОЖАЕТСЯ',
};
const PROFILE_COPY = {
  body: 'Жук падает, распластывает ноги и остаётся физической тушей.',
  char: 'Корпус темнеет, дымится, выпускает угли и осыпается.',
  crush: 'Тело расплющивается, оставляя тёмный след и куски панциря.',
  melt: 'Модель оплывает в цветную лужу с пузырьками и испарениями.',
  brittle: 'Тело покрывается инеем; после этого его можно расколоть.',
  dissolve: 'Модель растворяется в цветных частицах над следом на полу.',
  gib: 'От модели отлетают лапы, жвала и мелкие фрагменты.',
  destroy: 'Короткая вспышка, рассеивание частиц и исчезновение модели.',
};
const UNIQUE_SAMPLE_KEYS = {
  body: 'Water', char: 'Fire', crush: 'Earth', melt: 'Lava',
  brittle: 'Cold', dissolve: 'Acid', gib: 'Gunpowder', destroy: 'Star',
};
const MODE_FLAGS = {
  killDamage: 'Удар по области',
  killZone: 'Зона при смерти',
  killHeal: 'Растение / лечение',
  killBarrier: 'Преграда при смерти',
  deathMark: 'Метка смерти',
  terrain: 'Меняет ландшафт',
};
const MODE_HINT = {
  body: 'Падение и физическая туша',
  char: 'Обугливание и осыпание',
  crush: 'Расплющивание и обломки',
  melt: 'Плавление и лужа',
  brittle: 'Иней и раскол',
  dissolve: 'Растворение',
  gib: 'Разлёт частей',
  destroy: 'Вспышка и исчезновение',
};

const palette = {
  bg: 0x071012,
  floor: 0x111e21,
  grid: 0x213638,
  accent: 0x67d5c0,
  warm: 0xedaa62,
};

const items = ELEMENTS.map((record) => ({ ...record, profile: record.mode ?? 'body' }));
items.sort((a, b) => a.name.localeCompare(b.name, 'ru'));
const itemsByKey = new Map(items.map((item) => [item.key, item]));
const uniqueItems = PROFILE_ORDER
  .map((profile) => {
    const chosen = itemsByKey.get(UNIQUE_SAMPLE_KEYS[profile]);
    return chosen?.profile === profile ? chosen : items.find((item) => item.profile === profile);
  })
  .filter(Boolean);

const dom = {
  canvas: $('#scene-canvas'),
  stage: $('#stage-frame'),
  loader: $('#loader-overlay'),
  warning: $('#scene-warning'),
  hint: $('#scene-hint'),
  list: $('#element-list'),
  listCount: $('#list-count'),
  search: $('#search'),
  allMode: $('#all-mode'),
  uniqueMode: $('#unique-mode'),
  name: $('#element-name'),
  key: $('#element-key'),
  swatch: $('#element-swatch'),
  hex: $('#element-hex'),
  profile: $('#profile-name'),
  profileCode: $('#profile-code'),
  profileDot: $('#profile-dot'),
  description: $('#profile-description'),
  features: $('#feature-list'),
  special: $('#element-special'),
  sceneName: $('#scene-element-name'),
  sceneKey: $('#scene-element-key'),
  sceneStatus: $('#scene-status'),
  play: $('#play'),
  previous: $('#previous'),
  next: $('#next'),
  shatter: $('#shatter'),
  playbackStatus: $('#playback-status'),
  progress: $('#progress-bar'),
  progressLabel: $('#progress-label'),
  speed: $('#speed'),
  resetCamera: $('#reset-camera'),
  fullscreen: $('#fullscreen'),
};

let selected = itemsByKey.get('Fire') ?? items[0];
let uniqueMode = false;
let currentRows = items;
let visibleRows = items;
let modelTemplate = null;
let scene = null;
let camera = null;
let renderer = null;
let controls = null;
let modelRoot = null;
let modelObject = null;
let modelMeshes = [];
let particleList = [];
let fragments = [];
let transientObjects = [];
let animation = null;
let paused = false;
let shatterDone = false;
let lastParticleAt = 0;
let hintDismissed = false;
let clock = new THREE.Clock();
const PROJECTILE_TIME = 0.58;
const DEATH_DURATION = 3.1;
const MODEL_SCALE = 2.45;
const focusPoint = new THREE.Vector3(0, 1.18, 0);

const clamp01 = (n) => Math.max(0, Math.min(1, n));
const easeOut = (n) => 1 - (1 - clamp01(n)) ** 3;
const easeInOut = (n) => {
  const x = clamp01(n);
  return x < 0.5 ? 4 * x ** 3 : 1 - ((-2 * x + 2) ** 3) / 2;
};
const toThreeColor = (rgb) => new THREE.Color().setRGB(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255);
const toHex = (rgb) => `#${rgb.map((v) => Math.round(v).toString(16).padStart(2, '0')).join('')}`.toUpperCase();
const itemColor = (item) => toThreeColor(item?.color ?? [103, 213, 192]);

function initializeScene() {
  try {
    renderer = new THREE.WebGLRenderer({ canvas: dom.canvas, antialias: true, alpha: false, powerPreference: 'high-performance' });
  } catch (error) {
    showWarning('WebGL не запустился в этом браузере. Попробуй включить аппаратное ускорение или открыть страницу в другом браузере.');
    throw error;
  }

  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.setClearColor(palette.bg, 1);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.15;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;

  scene = new THREE.Scene();
  scene.background = new THREE.Color(palette.bg);
  scene.fog = new THREE.FogExp2(palette.bg, 0.022);

  camera = new THREE.PerspectiveCamera(34, 1, 0.1, 90);
  camera.position.set(6.6, 5.0, 10.7);
  controls = new OrbitControls(camera, renderer.domElement);
  controls.target.copy(focusPoint);
  controls.enableDamping = true;
  controls.dampingFactor = 0.07;
  controls.minDistance = 6.2;
  controls.maxDistance = 20;
  controls.maxPolarAngle = Math.PI * 0.485;
  controls.minPolarAngle = 0.12;
  controls.autoRotate = false;
  controls.update();

  const hemi = new THREE.HemisphereLight(0xc7f2e6, 0x17211e, 2.0);
  scene.add(hemi);

  const keyLight = new THREE.DirectionalLight(0xffeed2, 4.0);
  keyLight.position.set(-5, 8, 5);
  keyLight.castShadow = true;
  keyLight.shadow.mapSize.set(1024, 1024);
  keyLight.shadow.camera.near = 0.5;
  keyLight.shadow.camera.far = 24;
  keyLight.shadow.camera.left = -8;
  keyLight.shadow.camera.right = 8;
  keyLight.shadow.camera.top = 8;
  keyLight.shadow.camera.bottom = -8;
  keyLight.shadow.bias = -0.00025;
  scene.add(keyLight);

  const rimLight = new THREE.DirectionalLight(0x6fdac6, 3.2);
  rimLight.position.set(5, 4, -6);
  scene.add(rimLight);

  const fillLight = new THREE.PointLight(0x507e98, 24, 18, 2);
  fillLight.position.set(1, 3.5, 5);
  scene.add(fillLight);

  const ground = new THREE.Mesh(
    new THREE.PlaneGeometry(120, 120),
    new THREE.MeshStandardMaterial({ color: 0x0a1417, roughness: 0.92, metalness: 0.12 })
  );
  ground.rotation.x = -Math.PI / 2;
  ground.position.y = -0.15;
  ground.receiveShadow = true;
  ground.name = 'LaboratoryFloor';
  scene.add(ground);

  const platform = new THREE.Mesh(
    new THREE.CylinderGeometry(4.1, 4.25, 0.18, 72, 1, false),
    new THREE.MeshStandardMaterial({ color: 0x172629, roughness: 0.48, metalness: 0.62 })
  );
  platform.position.y = -0.07;
  platform.receiveShadow = true;
  platform.castShadow = true;
  scene.add(platform);

  const platformEdge = new THREE.Mesh(
    new THREE.TorusGeometry(4.0, 0.035, 8, 96),
    new THREE.MeshBasicMaterial({ color: 0x3a887b, transparent: true, opacity: 0.68 })
  );
  platformEdge.rotation.x = Math.PI / 2;
  platformEdge.position.y = 0.035;
  scene.add(platformEdge);

  const grid = new THREE.GridHelper(48, 48, 0x2b4d4b, 0x172a2d);
  grid.position.y = -0.135;
  grid.material.transparent = true;
  grid.material.opacity = 0.38;
  scene.add(grid);

  for (const [radius, opacity] of [[5.4, 0.18], [7.2, 0.11]]) {
    const ring = new THREE.Mesh(
      new THREE.TorusGeometry(radius, 0.012, 6, 128),
      new THREE.MeshBasicMaterial({ color: 0x51988a, transparent: true, opacity })
    );
    ring.rotation.x = Math.PI / 2;
    ring.position.y = -0.135;
    scene.add(ring);
  }

  const resize = () => {
    if (!renderer || !camera) return;
    const rect = dom.stage.getBoundingClientRect();
    const width = Math.max(1, Math.floor(rect.width));
    const height = Math.max(1, Math.floor(rect.height));
    renderer.setSize(width, height, false);
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
  };
  new ResizeObserver(resize).observe(dom.stage);
  window.addEventListener('resize', resize);
  resize();
  return renderer;
}

function showWarning(message) {
  dom.warning.textContent = message;
  dom.warning.hidden = false;
}

function clearWarning() {
  dom.warning.hidden = true;
  dom.warning.textContent = '';
}

function colorMaterials(root, tint, amount, opacity = 1, emissive = null) {
  root.traverse((object) => {
    if (!object.isMesh) return;
    const materials = Array.isArray(object.material) ? object.material : [object.material];
    const snapshots = object.userData.baseMaterials;
    if (!snapshots) return;
    materials.forEach((material, index) => {
      const base = snapshots[index];
      if (material.color && base.color) material.color.copy(base.color).lerp(tint, amount);
      if (material.emissive && base.emissive) {
        material.emissive.copy(base.emissive);
        if (emissive) material.emissive.lerp(emissive, amount);
      }
      if ('emissiveIntensity' in material) material.emissiveIntensity = base.emissiveIntensity + amount * (emissive ? 0.55 : 0);
      if ('transparent' in material) material.transparent = opacity < 0.995 || base.transparent;
      if ('opacity' in material) material.opacity = base.opacity * opacity;
      material.depthWrite = opacity > 0.85 && base.depthWrite;
      material.needsUpdate = true;
    });
  });
}

function disposeModelMaterials(root) {
  root?.traverse((object) => {
    if (!object.isMesh || !object.material) return;
    const materials = Array.isArray(object.material) ? object.material : [object.material];
    materials.forEach((material) => material.dispose());
  });
}

function makeModel() {
  if (!modelTemplate || !scene) return;
  if (modelRoot) {
    disposeModelMaterials(modelObject);
    scene.remove(modelRoot);
    modelRoot = null;
    modelObject = null;
    modelMeshes = [];
  }

  modelRoot = new THREE.Group();
  modelRoot.name = 'LivingBeetle';
  modelObject = modelTemplate.clone(true);
  modelObject.name = 'StandardBeetleGLB';

  modelObject.traverse((object) => {
    if (!object.isMesh) return;
    object.castShadow = true;
    object.receiveShadow = true;
    if (Array.isArray(object.material)) {
      object.material = object.material.map((material) => material.clone());
    } else if (object.material) {
      object.material = object.material.clone();
    }
    const materials = Array.isArray(object.material) ? object.material : [object.material];
    object.userData.baseMaterials = materials.map((material) => ({
      color: material.color?.clone() ?? new THREE.Color(0xffffff),
      emissive: material.emissive?.clone() ?? new THREE.Color(0x000000),
      emissiveIntensity: material.emissiveIntensity ?? 0,
      opacity: material.opacity ?? 1,
      transparent: material.transparent ?? false,
      depthWrite: material.depthWrite ?? true,
    }));
    modelMeshes.push(object);
  });

  modelObject.updateMatrixWorld(true);
  const bounds = new THREE.Box3().setFromObject(modelObject);
  const center = bounds.getCenter(new THREE.Vector3());
  const minY = bounds.min.y;
  modelObject.scale.setScalar(MODEL_SCALE);
  modelObject.position.set(-center.x * MODEL_SCALE, -minY * MODEL_SCALE, -center.z * MODEL_SCALE);
  modelRoot.add(modelObject);
  modelRoot.position.set(0, 0, 0);
  modelRoot.rotation.y = -0.22;
  scene.add(modelRoot);
}

function disposeTransient(object) {
  scene?.remove(object);
  object.traverse?.((child) => {
    if (child.geometry && !child.userData.sharedGeometry) child.geometry.dispose();
    if (child.material) {
      const materials = Array.isArray(child.material) ? child.material : [child.material];
      materials.forEach((material) => material.dispose());
    }
  });
}

function clearEffects() {
  for (const particle of particleList) disposeTransient(particle.mesh);
  particleList = [];
  for (const fragment of fragments) disposeTransient(fragment.mesh);
  fragments = [];
  for (const object of transientObjects) disposeTransient(object);
  transientObjects = [];
}

function spawnPool(color, maxRadius = 2.1, opacity = 0.4) {
  const mesh = new THREE.Mesh(
    new THREE.CircleGeometry(1, 56),
    new THREE.MeshStandardMaterial({
      color,
      emissive: color,
      emissiveIntensity: 0.18,
      roughness: 0.28,
      metalness: 0.12,
      transparent: true,
      opacity: 0.02,
      depthWrite: false,
      side: THREE.DoubleSide,
    })
  );
  mesh.rotation.x = -Math.PI / 2;
  mesh.position.set(0, 0.018, 0);
  mesh.scale.set(0.15, 0.15, 0.15);
  mesh.userData.pool = { maxRadius, maxOpacity: opacity };
  scene.add(mesh);
  transientObjects.push(mesh);
  return mesh;
}

function spawnRing(position, color, radius = 0.6) {
  const ring = new THREE.Mesh(
    new THREE.TorusGeometry(1, 0.025, 7, 64),
    new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.95 })
  );
  ring.rotation.x = Math.PI / 2;
  ring.position.copy(position);
  ring.scale.setScalar(radius);
  ring.userData.ring = { scale: radius, age: 0 };
  scene.add(ring);
  transientObjects.push(ring);
  return ring;
}

function burstParticles(position, color, count = 20, style = 'spark', power = 1) {
  const color3 = color?.isColor ? color : new THREE.Color(color);
  const geometryFactory = style === 'shard'
    ? () => new THREE.TetrahedronGeometry(0.12 + Math.random() * 0.12, 0)
    : style === 'smoke'
      ? () => new THREE.SphereGeometry(0.11 + Math.random() * 0.16, 7, 6)
      : () => new THREE.IcosahedronGeometry(0.045 + Math.random() * 0.05, 0);

  for (let index = 0; index < count; index += 1) {
    const material = style === 'smoke'
      ? new THREE.MeshBasicMaterial({ color: 0x9da59b, transparent: true, opacity: 0.24, depthWrite: false })
      : new THREE.MeshStandardMaterial({
          color: color3.clone().lerp(new THREE.Color(0xffedcf), Math.random() * 0.24),
          emissive: color3,
          emissiveIntensity: style === 'shard' ? 0.08 : 0.42,
          roughness: 0.43,
          metalness: style === 'shard' ? 0.2 : 0.03,
          transparent: true,
          opacity: 1,
        });
    const mesh = new THREE.Mesh(geometryFactory(), material);
    mesh.position.copy(position).add(new THREE.Vector3(
      (Math.random() - 0.5) * 0.95,
      (Math.random() - 0.5) * 0.75,
      (Math.random() - 0.5) * 0.95
    ));
    mesh.rotation.set(Math.random() * 3, Math.random() * 3, Math.random() * 3);
    mesh.castShadow = style === 'shard';
    scene.add(mesh);
    const direction = new THREE.Vector3(Math.random() - 0.5, Math.random() * 0.9 + 0.15, Math.random() - 0.5).normalize();
    const speed = (style === 'smoke' ? 0.5 : 1.8 + Math.random() * 3.4) * power;
    particleList.push({
      mesh,
      velocity: direction.multiplyScalar(speed),
      spin: new THREE.Vector3((Math.random() - 0.5) * 8, (Math.random() - 0.5) * 8, (Math.random() - 0.5) * 8),
      life: style === 'smoke' ? 1.4 + Math.random() * 1.3 : 0.9 + Math.random() * 1.25,
      age: 0,
      gravity: style === 'smoke' ? -0.12 : 5.4,
      style,
    });
  }
}

function makeProjectile(color) {
  const group = new THREE.Group();
  group.name = 'ElementProjectile';
  const core = new THREE.Mesh(
    new THREE.SphereGeometry(0.14, 18, 14),
    new THREE.MeshStandardMaterial({ color, emissive: color, emissiveIntensity: 2.2, roughness: 0.22, metalness: 0.12 })
  );
  const halo = new THREE.Mesh(
    new THREE.SphereGeometry(0.27, 16, 12),
    new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.2, depthWrite: false })
  );
  group.add(core, halo);
  const light = new THREE.PointLight(color, 7, 4.5, 2);
  group.add(light);

  const trailGeometry = new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(), new THREE.Vector3(-0.9, 0, 0)]);
  const trail = new THREE.Line(trailGeometry, new THREE.LineBasicMaterial({ color, transparent: true, opacity: 0.72 }));
  group.add(trail);
  scene.add(group);
  transientObjects.push(group);
  return { group, core, halo, trail, trailGeometry };
}

function impactBurst(item) {
  const color = itemColor(item);
  const point = new THREE.Vector3(0, 1.12, 0.64);
  const flash = new THREE.Mesh(
    new THREE.SphereGeometry(0.22, 18, 14),
    new THREE.MeshBasicMaterial({ color: 0xfff3d7, transparent: true, opacity: 1 })
  );
  flash.position.copy(point);
  flash.userData.impact = true;
  scene.add(flash);
  transientObjects.push(flash);
  const light = new THREE.PointLight(color, 24, 9, 2);
  light.position.copy(point);
  light.userData.impactLight = true;
  scene.add(light);
  transientObjects.push(light);
  spawnRing(point, color, 0.22);
  burstParticles(point, color, 13, 'spark', 0.75);
}

function spawnMeshFragments(which, color, maxCount = 12, power = 1.1) {
  if (!modelObject || !modelRoot) return;
  modelRoot.updateMatrixWorld(true);
  const isCandidate = (name) => {
    if (which === 'shell') return /^(BeetlePlate|elytra_spot|HeadBase)/i.test(name);
    if (which === 'limbs') return /^(Tibia|Tarsus1|Tarsus2|MandibleTip|AntSeg4)/i.test(name);
    if (which === 'burst') return /^(BeetlePlate|HeadBase|MandibleTip|Tibia)/i.test(name);
    return false;
  };
  const candidates = modelMeshes.filter((mesh) => mesh.visible && isCandidate(mesh.name));
  const selectedMeshes = candidates.slice(0, maxCount);
  for (const mesh of selectedMeshes) {
    const worldPosition = new THREE.Vector3();
    const worldQuaternion = new THREE.Quaternion();
    const worldScale = new THREE.Vector3();
    mesh.getWorldPosition(worldPosition);
    mesh.getWorldQuaternion(worldQuaternion);
    mesh.getWorldScale(worldScale);

    const fragment = new THREE.Mesh(mesh.geometry, Array.isArray(mesh.material)
      ? mesh.material.map((material) => material.clone())
      : mesh.material.clone());
    fragment.name = `${mesh.name}_fragment`;
    fragment.position.copy(worldPosition);
    fragment.quaternion.copy(worldQuaternion);
    fragment.scale.copy(worldScale);
    fragment.castShadow = true;
    fragment.receiveShadow = true;
    fragment.userData.sharedGeometry = true;
    fragment.traverse((child) => {
      if (!child.isMesh) return;
      const materials = Array.isArray(child.material) ? child.material : [child.material];
      materials.forEach((material) => {
        if (material.color) material.color.lerp(color, 0.2);
        material.transparent = true;
        material.opacity = 1;
        material.needsUpdate = true;
      });
    });
    scene.add(fragment);
    fragments.push({
      mesh: fragment,
      velocity: new THREE.Vector3((Math.random() - 0.5) * 5 * power, (1.1 + Math.random() * 3.5) * power, (Math.random() - 0.5) * 5 * power),
      spin: new THREE.Vector3((Math.random() - 0.5) * 7, (Math.random() - 0.5) * 7, (Math.random() - 0.5) * 7),
      age: 0,
      life: 2.2 + Math.random() * 1.4,
    });
    mesh.visible = false;
  }
  return selectedMeshes.length;
}

function resetDemo(item = selected, { autoPlay = true } = {}) {
  if (!modelTemplate || !scene || !item) return;
  clearEffects();
  makeModel();
  selected = item;
  shatterDone = false;
  dom.shatter.hidden = true;
  dom.sceneName.textContent = item.name;
  dom.sceneKey.textContent = `${item.key}  /  ${item.profile.toUpperCase()}`;
  dom.sceneStatus.textContent = 'ГОТОВ К ПОПАДАНИЮ';
  dom.progress.style.width = '0%';
  dom.progressLabel.textContent = '0%';
  if (!autoPlay) {
    animation = null;
    paused = false;
    dom.play.classList.remove('playing');
    dom.play.innerHTML = '▶ <span>СМОТРЕТЬ СМЕРТЬ</span>';
    dom.playbackStatus.textContent = 'ГОТОВ К ДЕМОНСТРАЦИИ';
    return;
  }
  startAnimation(item);
}

function startAnimation(item = selected) {
  if (!modelTemplate || !scene || !modelRoot || !item) return;
  clearEffects();
  if (!modelRoot.parent) scene.add(modelRoot);
  modelRoot.position.set(0, 0, 0);
  modelRoot.rotation.set(0, -0.22, 0);
  modelRoot.scale.setScalar(1);
  modelMeshes.forEach((mesh) => { mesh.visible = true; });
  colorMaterials(modelObject, new THREE.Color(0xffffff), 0, 1);

  selected = item;
  const color = itemColor(item);
  const start = new THREE.Vector3(-6.0, 2.5, 1.6);
  const end = new THREE.Vector3(0, 1.2, 0.65);
  const projectile = makeProjectile(color);
  projectile.group.position.copy(start);
  animation = {
    item,
    time: 0,
    total: PROJECTILE_TIME + DEATH_DURATION,
    deathStarted: false,
    projectile,
    start,
    end,
    pool: null,
    lastSmoke: 0,
    lastEmber: 0,
    fragmentBurst: false,
    ring: null,
    pausable: true,
  };
  paused = false;
  shatterDone = false;
  dom.shatter.hidden = true;
  dom.play.classList.add('playing');
  dom.play.innerHTML = 'Ⅱ <span>ПАУЗА</span>';
  dom.playbackStatus.textContent = `СНАРЯД ${item.name.toLocaleUpperCase('ru')} · В ПОЛЁТЕ`;
  dom.sceneStatus.textContent = 'ПОЛЁТ СНАРЯДА';
  dom.progress.style.width = '0%';
  dom.progressLabel.textContent = '0%';
}

function beginDeath(item) {
  if (!animation || animation.deathStarted) return;
  animation.deathStarted = true;
  animation.deathAt = animation.time;
  if (animation.projectile?.group) {
    const projectileGroup = animation.projectile.group;
    transientObjects = transientObjects.filter((entry) => entry !== projectileGroup);
    disposeTransient(projectileGroup);
    animation.projectile = null;
  }
  impactBurst(item);
  const color = itemColor(item);
  if (['crush', 'melt', 'dissolve'].includes(item.profile)) {
    animation.pool = spawnPool(item.profile === 'crush' ? new THREE.Color(0x3b3028) : color,
      item.profile === 'crush' ? 2.65 : 2.25,
      item.profile === 'crush' ? 0.58 : 0.47);
  }
  animation.ring = spawnRing(new THREE.Vector3(0, 0.08, 0), color, 0.16);
  dom.playbackStatus.textContent = `${PROFILE_LABELS[item.profile]} · ${item.name.toLocaleUpperCase('ru')}`;
  dom.sceneStatus.textContent = 'ПОПАДАНИЕ · СИМУЛЯЦИЯ ОСТАНКОВ';
}

function updateProjectile(anim) {
  const progress = clamp01(anim.time / PROJECTILE_TIME);
  const eased = easeInOut(progress);
  const position = anim.start.clone().lerp(anim.end, eased);
  position.y += Math.sin(progress * Math.PI) * 0.55;
  const { group, trailGeometry } = anim.projectile;
  group.position.copy(position);
  group.rotation.y = -Math.PI / 2;
  const tailEnd = position.clone().lerp(anim.start, 0.11 + 0.08 * Math.sin(progress * Math.PI));
  trailGeometry.setFromPoints([position.clone(), tailEnd]);
  trailGeometry.attributes.position.needsUpdate = true;
  if (progress >= 1) beginDeath(anim.item);
}

function updatePool(anim, deathTime, delta) {
  if (!anim.pool) return;
  const poolData = anim.pool.userData.pool;
  const grow = easeOut(Math.min(deathTime / 1.35, 1));
  const radius = 0.15 + poolData.maxRadius * grow;
  anim.pool.scale.set(radius, radius * 0.72, radius);
  const fade = deathTime > 2.8 ? Math.max(0, 1 - (deathTime - 2.8) / 1.4) : 1;
  anim.pool.material.opacity = poolData.maxOpacity * grow * fade;
  anim.pool.material.emissiveIntensity = 0.12 + Math.sin(anim.time * 4) * 0.055;
  if (deathTime > 1.1 && anim.item.profile !== 'crush' && anim.time - anim.lastSmoke > 0.32) {
    anim.lastSmoke = anim.time;
    const pos = new THREE.Vector3((Math.random() - 0.5) * 1.15, 0.35, (Math.random() - 0.5) * 0.9);
    burstParticles(pos, itemColor(anim.item), 2, 'smoke', 0.55);
  }
}

function updateDeathAnimation(anim, deathTime, delta) {
  if (!modelRoot || !modelObject) return;
  const item = anim.item;
  const profile = item.profile;
  const e = easeOut(deathTime / DEATH_DURATION);
  const color = itemColor(item);
  const center = new THREE.Vector3(0, 0.9, 0.35);

  if (anim.ring) {
    const ringAge = Math.max(0, deathTime - 0.02);
    const scale = 0.16 + ringAge * 2.1;
    anim.ring.scale.set(scale, scale, scale);
    anim.ring.material.opacity = Math.max(0, 0.82 - ringAge * 0.68);
  }

  if (profile === 'body') {
    const fall = easeOut(deathTime / 0.76);
    modelRoot.rotation.z = -0.82 * fall;
    modelRoot.rotation.x = 0.12 * fall;
    modelRoot.position.y = -0.1 * fall;
    colorMaterials(modelObject, new THREE.Color(0x696f64), Math.min(0.57, e * 0.57), 1);
    if (deathTime > 0.55 && anim.time - anim.lastSmoke > 0.55) {
      anim.lastSmoke = anim.time;
      burstParticles(new THREE.Vector3(0, 0.24, 0), new THREE.Color(0x847f73), 3, 'smoke', 0.28);
    }
  } else if (profile === 'char') {
    const fall = easeOut(deathTime / 0.65);
    modelRoot.rotation.z = -0.42 * fall;
    modelRoot.position.y = -0.13 * fall;
    const charAmount = Math.min(0.92, e * 0.98);
    colorMaterials(modelObject, new THREE.Color(0x2d2925), charAmount, deathTime > 2.1 ? 1 - clamp01((deathTime - 2.1) / 1.05) * 0.55 : 1, new THREE.Color(0x4f2817));
    if (deathTime - anim.lastSmoke > 0.17 && deathTime < 2.7) {
      anim.lastSmoke = deathTime;
      burstParticles(new THREE.Vector3((Math.random() - 0.5) * 0.9, 0.7 + Math.random() * 0.7, (Math.random() - 0.5) * 0.8), 0x79776e, 2, 'smoke', 0.38);
    }
    if (deathTime - anim.lastEmber > 0.21 && deathTime < 2.2) {
      anim.lastEmber = deathTime;
      burstParticles(center, Math.random() > 0.5 ? 0xff923f : 0xf5ca61, 2, 'spark', 0.43);
    }
  } else if (profile === 'crush') {
    modelRoot.scale.set(1 + e * 0.28, Math.max(0.12, 1 - e * 0.82), 1 + e * 0.25);
    modelRoot.position.y = 0.04;
    colorMaterials(modelObject, new THREE.Color(0x3c352f), e * 0.52, 1);
    if (!anim.fragmentBurst && deathTime > 0.44) {
      anim.fragmentBurst = true;
      spawnMeshFragments('shell', color, 5, 0.58);
      burstParticles(new THREE.Vector3(0, 0.35, 0), 0x9d795a, 17, 'shard', 0.62);
    }
  } else if (profile === 'melt') {
    const fade = 1 - clamp01((deathTime - 0.25) / 1.55);
    modelRoot.scale.set(1 + e * 0.16, Math.max(0.08, 1 - e * 0.9), 1 + e * 0.18);
    modelRoot.position.y = -0.09 * e;
    colorMaterials(modelObject, color, Math.min(0.78, e * 0.8), Math.max(0.03, fade), color);
    if (deathTime > 0.45 && anim.time - anim.lastEmber > 0.24) {
      anim.lastEmber = anim.time;
      burstParticles(new THREE.Vector3((Math.random() - 0.5) * 0.85, 0.18, (Math.random() - 0.5) * 0.75), color, 3, 'spark', 0.38);
    }
  } else if (profile === 'brittle') {
    colorMaterials(
      modelObject,
      new THREE.Color(0x9ddfff),
      Math.min(0.88, e * 1.2),
      shatterDone ? 0.08 : 1,
      new THREE.Color(0x4bbde9)
    );
    if (!shatterDone && deathTime > 0.52 && anim.time - anim.lastEmber > 0.38) {
      anim.lastEmber = anim.time;
      burstParticles(center.clone().add(new THREE.Vector3((Math.random() - 0.5), 0.2, (Math.random() - 0.5))), 0xb8eaff, 2, 'spark', 0.32);
    }
    if (!shatterDone && deathTime > 0.88) {
      dom.shatter.hidden = false;
      dom.shatter.disabled = false;
      dom.playbackStatus.textContent = 'ХРУПКИЙ ТРУП · МОЖНО РАСКОЛОТЬ';
    }
  } else if (profile === 'dissolve') {
    const fade = 1 - clamp01((deathTime - 0.18) / 1.75);
    modelRoot.position.y = -0.13 * e;
    modelRoot.scale.set(1 + e * 0.12, Math.max(0.12, 1 - e * 0.72), 1 + e * 0.12);
    colorMaterials(modelObject, color, Math.min(0.68, e * 0.75), Math.max(0.015, fade), color);
    if (deathTime - anim.lastSmoke > 0.12 && deathTime < 2.3) {
      anim.lastSmoke = deathTime;
      burstParticles(new THREE.Vector3((Math.random() - 0.5) * 1.1, Math.random() * 0.95 + 0.2, (Math.random() - 0.5) * 0.9), color, 2, 'spark', 0.32);
    }
  } else if (profile === 'gib') {
    const fade = 1 - clamp01((deathTime - 0.24) / 1.2);
    modelRoot.rotation.z = -0.2 * e;
    colorMaterials(modelObject, new THREE.Color(0x7b4135), e * 0.36, Math.max(0.02, fade));
    if (!anim.fragmentBurst && deathTime > 0.25) {
      anim.fragmentBurst = true;
      const detached = spawnMeshFragments('limbs', color, 18, 1.28);
      burstParticles(center, 0x9d5145, Math.max(12, detached), 'shard', 1.0);
    }
    if (deathTime - anim.lastSmoke > 0.42 && deathTime < 1.8) {
      anim.lastSmoke = deathTime;
      burstParticles(new THREE.Vector3(0, 0.2, 0), 0x984e42, 3, 'smoke', 0.32);
    }
  } else if (profile === 'destroy') {
    const flashIn = clamp01(deathTime / 0.22);
    const fade = 1 - clamp01((deathTime - 0.12) / 0.62);
    modelRoot.scale.setScalar(1 + Math.sin(flashIn * Math.PI) * 0.14 + e * 0.08);
    colorMaterials(modelObject, new THREE.Color(0xfff2c8), Math.min(1, flashIn * 0.82), Math.max(0.001, fade), new THREE.Color(0xffd779));
    if (!anim.fragmentBurst && deathTime > 0.1) {
      anim.fragmentBurst = true;
      spawnMeshFragments('burst', color, 9, 1.45);
      burstParticles(center, 0xffe2a0, 30, 'spark', 1.4);
    }
  }
}

function shatterBrittle() {
  if (!animation || animation.item.profile !== 'brittle' || shatterDone) return;
  shatterDone = true;
  dom.shatter.disabled = true;
  dom.shatter.hidden = true;
  spawnMeshFragments('shell', new THREE.Color(0xa9ddf3), 12, 1.55);
  burstParticles(new THREE.Vector3(0, 0.9, 0), new THREE.Color(0xd8f4ff), 28, 'shard', 1.15);
  colorMaterials(modelObject, new THREE.Color(0x9ddfff), 1, 0.08, new THREE.Color(0x4bbde9));
  paused = true;
  dom.play.classList.remove('playing');
  dom.play.innerHTML = '↻ <span>ПОВТОРИТЬ СМЕРТЬ</span>';
  dom.playbackStatus.textContent = 'РАСКОЛОТ · ЛЕДЯНЫЕ ОСКОЛКИ';
  dom.sceneStatus.textContent = 'ХРУПКИЙ ТРУП РАСКОЛОТ';
}

function updateParticles(delta) {
  for (let index = particleList.length - 1; index >= 0; index -= 1) {
    const particle = particleList[index];
    particle.age += delta;
    const t = clamp01(particle.age / particle.life);
    particle.velocity.y -= particle.gravity * delta;
    particle.mesh.position.addScaledVector(particle.velocity, delta);
    particle.mesh.rotation.x += particle.spin.x * delta;
    particle.mesh.rotation.y += particle.spin.y * delta;
    particle.mesh.rotation.z += particle.spin.z * delta;
    if (particle.style !== 'smoke' && particle.mesh.position.y < 0.06) {
      particle.mesh.position.y = 0.06;
      particle.velocity.y = Math.abs(particle.velocity.y) * 0.22;
      particle.velocity.x *= 0.76;
      particle.velocity.z *= 0.76;
    }
    if (particle.style === 'smoke') {
      const scale = 1 + t * 2.3;
      particle.mesh.scale.setScalar(scale);
      particle.mesh.material.opacity = 0.25 * (1 - t);
    } else {
      particle.mesh.material.opacity = 1 - t;
      particle.mesh.scale.multiplyScalar(1 - delta * (particle.style === 'shard' ? 0.09 : 0.42));
    }
    if (t >= 1) {
      disposeTransient(particle.mesh);
      particleList.splice(index, 1);
    }
  }

  for (let index = fragments.length - 1; index >= 0; index -= 1) {
    const fragment = fragments[index];
    fragment.age += delta;
    fragment.velocity.y -= 5.8 * delta;
    fragment.mesh.position.addScaledVector(fragment.velocity, delta);
    fragment.mesh.rotation.x += fragment.spin.x * delta;
    fragment.mesh.rotation.y += fragment.spin.y * delta;
    fragment.mesh.rotation.z += fragment.spin.z * delta;
    if (fragment.mesh.position.y < 0.035) {
      fragment.mesh.position.y = 0.035;
      fragment.velocity.y = Math.abs(fragment.velocity.y) * 0.28;
      fragment.velocity.x *= 0.77;
      fragment.velocity.z *= 0.77;
    }
    const fade = clamp01((fragment.age - fragment.life + 0.8) / 0.8);
    const materials = Array.isArray(fragment.mesh.material) ? fragment.mesh.material : [fragment.mesh.material];
    materials.forEach((material) => {
      material.opacity = 1 - fade;
      material.needsUpdate = true;
    });
    if (fragment.age >= fragment.life) {
      disposeTransient(fragment.mesh);
      fragments.splice(index, 1);
    }
  }

  for (const object of transientObjects) {
    if (object.userData.ring) {
      object.userData.ring.age += delta;
      const ringData = object.userData.ring;
      const spread = ringData.scale + ringData.age * 2.1;
      object.scale.set(spread, spread, spread);
      object.material.opacity = Math.max(0, 0.9 - ringData.age * 0.72);
    }
    if (object.userData.impact) {
      object.scale.setScalar(1 + delta * 12);
      object.material.opacity = Math.max(0, object.material.opacity - delta * 4.2);
    }
    if (object.userData.impactLight) {
      object.intensity = Math.max(0, object.intensity - delta * 78);
    }
  }
}

function update(delta) {
  if (!renderer || !scene || !camera) return;
  controls?.update();
  if (animation && !paused) {
    const speed = Number(dom.speed.value) || 1;
    animation.time += Math.min(delta, 0.05) * speed;
    if (!animation.deathStarted) updateProjectile(animation);
    if (animation.deathStarted) {
      const deathTime = animation.time - animation.deathAt;
      updateDeathAnimation(animation, deathTime, delta * speed);
      updatePool(animation, deathTime, delta * speed);
      const progress = Math.min(1, animation.time / animation.total);
      dom.progress.style.width = `${Math.round(progress * 100)}%`;
      dom.progressLabel.textContent = `${Math.round(progress * 100)}%`;
      if (animation.time >= animation.total) {
        animation.time = animation.total;
        paused = true;
        dom.play.classList.remove('playing');
        dom.play.innerHTML = '↻ <span>ПОВТОРИТЬ СМЕРТЬ</span>';
        if (animation.item.profile !== 'brittle') dom.playbackStatus.textContent = `${PROFILE_LABELS[animation.item.profile]} · ГОТОВО`;
      }
    }
  }
  updateParticles(delta);
  renderer.render(scene, camera);
}

function frame() {
  requestAnimationFrame(frame);
  const delta = Math.min(clock.getDelta(), 0.08);
  update(delta);
}

function updateInspector(item) {
  if (!item) return;
  const hex = toHex(item.color);
  const cssColor = `rgb(${item.color.join(',')})`;
  dom.name.textContent = item.name;
  dom.key.textContent = item.key;
  dom.swatch.style.backgroundColor = cssColor;
  dom.swatch.style.color = cssColor;
  dom.hex.textContent = hex;
  dom.profile.textContent = PROFILE_LABELS[item.profile] ?? item.profile.toUpperCase();
  dom.profileCode.textContent = item.profile.toUpperCase();
  dom.profileDot.style.backgroundColor = cssColor;
  dom.profileDot.style.color = cssColor;
  dom.description.textContent = PROFILE_COPY[item.profile] ?? 'Анимация останков.';
  dom.sceneName.textContent = item.name;
  dom.sceneKey.textContent = `${item.key}  /  ${item.profile.toUpperCase()}`;

  dom.features.innerHTML = `
    <div class="feature-row"><span>Профиль</span><strong>${item.profile.toUpperCase()}</strong></div>
    <div class="feature-row"><span>Цвет снаряда</span><strong>${hex}</strong></div>
    <div class="feature-row"><span>Элементы в профиле</span><strong>${items.filter((entry) => entry.profile === item.profile).length}</strong></div>
  `;
  const flags = (item.flags ?? []).filter((flag) => MODE_FLAGS[flag]);
  if (flags.length) {
    dom.special.hidden = false;
    dom.special.innerHTML = `<b>Доп. свойства не проигрываются в этой сцене:</b><br>${flags.map((flag) => MODE_FLAGS[flag]).join(' · ')}`;
  } else {
    dom.special.hidden = true;
    dom.special.textContent = '';
  }
}

function buildRow(item, index) {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = `element-row${item === selected ? ' selected' : ''}`;
  button.setAttribute('role', 'option');
  button.setAttribute('aria-selected', item === selected ? 'true' : 'false');
  button.dataset.key = item.key;
  button.style.order = String(index);
  const hex = toHex(item.color);
  const right = uniqueMode ? item.profile.toUpperCase() : item.key;
  button.innerHTML = `<i class="row-swatch" style="background:${hex};color:${hex}"></i><span class="row-name"></span><span class="row-code"></span>`;
  button.querySelector('.row-name').textContent = item.name;
  button.querySelector('.row-code').textContent = right;
  button.addEventListener('click', () => {
    selected = item;
    updateInspector(item);
    renderList();
    resetDemo(item, { autoPlay: true });
  });
  return button;
}

function renderList() {
  currentRows = uniqueMode ? uniqueItems : items;
  const query = dom.search.value.trim().toLocaleLowerCase('ru');
  visibleRows = currentRows.filter((item) => `${item.name} ${item.key} ${item.profile}`.toLocaleLowerCase('ru').includes(query));
  dom.list.replaceChildren(...visibleRows.map(buildRow));
  dom.listCount.textContent = `${visibleRows.length} / ${currentRows.length} ПОКАЗАНО`;
  dom.allMode.classList.toggle('active', !uniqueMode);
  dom.uniqueMode.classList.toggle('active', uniqueMode);
}

function selectOffset(offset) {
  if (!visibleRows.length) return;
  const index = Math.max(0, visibleRows.indexOf(selected));
  const nextIndex = (index + offset + visibleRows.length) % visibleRows.length;
  selected = visibleRows[nextIndex];
  updateInspector(selected);
  renderList();
  resetDemo(selected, { autoPlay: true });
}

dom.allMode.addEventListener('click', () => {
  uniqueMode = false;
  if (!items.includes(selected)) selected = items[0];
  renderList();
  updateInspector(selected);
  resetDemo(selected, { autoPlay: true });
});
dom.uniqueMode.addEventListener('click', () => {
  uniqueMode = true;
  if (!uniqueItems.includes(selected)) selected = uniqueItems[0];
  renderList();
  updateInspector(selected);
  resetDemo(selected, { autoPlay: true });
});
dom.search.addEventListener('input', renderList);
dom.previous.addEventListener('click', () => selectOffset(-1));
dom.next.addEventListener('click', () => selectOffset(1));
dom.play.addEventListener('click', () => {
  if (!animation || animation.time >= animation.total) {
    resetDemo(selected, { autoPlay: true });
    return;
  }
  paused = !paused;
  dom.play.classList.toggle('playing', !paused);
  dom.play.innerHTML = paused ? '▶ <span>ПРОДОЛЖИТЬ</span>' : 'Ⅱ <span>ПАУЗА</span>';
  dom.playbackStatus.textContent = paused ? 'ПАУЗА' : 'ВОСПРОИЗВЕДЕНИЕ';
});
dom.shatter.addEventListener('click', shatterBrittle);
dom.resetCamera.addEventListener('click', () => {
  if (!camera || !controls) return;
  camera.position.set(6.6, 5.0, 10.7);
  controls.target.copy(focusPoint);
  controls.update();
});
dom.fullscreen.addEventListener('click', async () => {
  try {
    if (!document.fullscreenElement) await dom.stage.requestFullscreen();
    else await document.exitFullscreen();
  } catch { /* Полноэкранный режим может быть запрещён iframe-политикой браузера. */ }
});

window.addEventListener('keydown', (event) => {
  const target = event.target;
  if (target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement) {
    if (event.key === 'Escape') target.blur();
    return;
  }
  if (event.key === 'ArrowLeft') {
    event.preventDefault();
    selectOffset(-1);
  } else if (event.key === 'ArrowRight') {
    event.preventDefault();
    selectOffset(1);
  } else if (event.code === 'Space') {
    event.preventDefault();
    dom.play.click();
  } else if (event.key === '/') {
    event.preventDefault();
    dom.search.focus();
  }
});

dom.stage.addEventListener('pointerdown', () => {
  if (hintDismissed) return;
  hintDismissed = true;
  dom.hint.classList.add('hidden');
});

function loadModel() {
  const loader = new GLTFLoader();
  loader.load(
    '/models/standard_beetle.glb',
    (gltf) => {
      modelTemplate = gltf.scene;
      makeModel();
      dom.loader.classList.add('loaded');
      dom.sceneStatus.textContent = 'МОДЕЛЬ ЗАГРУЖЕНА';
      renderList();
      updateInspector(selected);
      startAnimation(selected);
    },
    (event) => {
      if (event.total > 0) {
        const percent = Math.round((event.loaded / event.total) * 100);
        const line = dom.loader.querySelector('span');
        if (line) line.textContent = `Загрузка GLB · ${percent}%`;
      }
    },
    (error) => {
      console.error('[3D Death Lab] Не удалось загрузить GLB:', error);
      dom.loader.classList.add('loaded');
      dom.sceneStatus.textContent = 'МОДЕЛЬ НЕ ЗАГРУЖЕНА';
      showWarning('Не удалось загрузить standard_beetle.glb. Проверь, что сервер запущен из tools/preview и файл public/models/standard_beetle.glb доступен.');
    }
  );
}

try {
  initializeScene();
  renderList();
  updateInspector(selected);
  frame();
  loadModel();
} catch (error) {
  console.error('[3D Death Lab] Ошибка инициализации WebGL:', error);
  showWarning('Не удалось создать WebGL-сцену. Попробуй перезагрузить страницу или включить аппаратное ускорение.');
}
