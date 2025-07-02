-- Adăugare coloană availability la tabela listings
ALTER TABLE listings ADD COLUMN IF NOT EXISTS availability text DEFAULT 'pe_stoc' CHECK (availability IN ('pe_stoc', 'la_comanda'));

-- Creare index pentru performanță
CREATE INDEX IF NOT EXISTS idx_listings_availability ON listings(availability);

-- Funcție pentru ștergerea completă a unui utilizator și a datelor asociate
CREATE OR REPLACE FUNCTION delete_user_complete(user_id_to_delete uuid)
RETURNS boolean AS $$
DECLARE
  profile_id uuid;
BEGIN
  -- Obține ID-ul profilului pentru acest utilizator
  SELECT id INTO profile_id FROM profiles WHERE user_id = user_id_to_delete;
  
  IF profile_id IS NULL THEN
    RAISE WARNING 'No profile found for user %', user_id_to_delete;
    RETURN false;
  END IF;
  
  -- Șterge toate anunțurile acestui utilizator
  DELETE FROM listings WHERE seller_id = profile_id;
  
  -- Șterge toate favoritele acestui utilizator
  DELETE FROM favorites WHERE user_id = user_id_to_delete;
  
  -- Șterge toate mesajele trimise de sau către acest utilizator
  DELETE FROM messages WHERE sender_id = user_id_to_delete OR receiver_id = user_id_to_delete;
  
  -- Șterge toate recenziile făcute de sau despre acest utilizator
  DELETE FROM reviews WHERE reviewer_id = user_id_to_delete OR reviewed_id = user_id_to_delete;
  
  -- Șterge profilul utilizatorului
  DELETE FROM profiles WHERE user_id = user_id_to_delete;
  
  RETURN true;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'Error deleting user %: %', user_id_to_delete, SQLERRM;
    RETURN false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;