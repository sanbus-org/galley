<template>
  <div class="banner-container">
    <img :src="bannerLight" alt="Galley Banner" class="galley-banner light-only">
    <img :src="bannerDark" alt="Galley Banner" class="galley-banner dark-only">
  </div>
</template>

<script setup>
import bannerLight from '../../../resources/banner-light.webp'
import bannerDark from '../../../resources/banner-dark.webp'
</script>

<style>
.banner-container {
  display: flex;
  justify-content: center;
  align-items: center;
  width: 100%;
  height: 100%;
}
.galley-banner {
  width: 100%;
  max-width: 550px;
  height: auto;
  border-radius: 12px;
  box-shadow: 0 10px 30px rgba(0,0,0,0.15);
  display: block;
}
html.dark .light-only {
  display: none !important;
}
html:not(.dark) .dark-only {
  display: none !important;
}
</style>
