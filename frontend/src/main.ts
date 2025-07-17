import { createApp } from 'vue'
import './style.css'
import App from './App.vue'
import { RequestOptions, setCommonFetchOptions } from './api/fetch.pb'

export const withPathPrefix = (prefix: string) => {
  return (req: RequestOptions) => {
    if (!req.url.startsWith(prefix)) {
      req.url = `${prefix}${req.url}`;
    }
  };
}

setCommonFetchOptions(withPathPrefix("/api"))

createApp(App).mount('#app')
