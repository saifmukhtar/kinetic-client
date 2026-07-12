import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { KineticControlCenter } from './app/KineticControlCenter';

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="*" element={<KineticControlCenter />} />
      </Routes>
    </BrowserRouter>
  );
}

export default App;
