import { mount } from 'svelte'
import RevocationForm from '@/components/RevocationForm.svelte'

const root = document.getElementById('revocation-form-root')
if (root) {
  mount(RevocationForm, { target: root })
}
