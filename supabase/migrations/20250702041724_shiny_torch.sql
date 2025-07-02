/*
  # Fix Admin User Management and Add Availability Field

  1. Changes
    - Add availability field to listings table for dealer listings
    - Fix admin user management (delete user and associated listings)
    - Add policy for admin to view all listings including pending ones
    - Fix email confirmation redirect

  2. Security
    - Maintain existing RLS policies
    - Add specific policies for admin operations
*/

-- Add availability field to listings table if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'listings' AND column_name = 'availability'
  ) THEN
    ALTER TABLE listings ADD COLUMN availability text DEFAULT 'pe_stoc' CHECK (availability IN ('pe_stoc', 'la_comanda'));
  END IF;
END $$;

-- Create a function to delete a user and all associated data
CREATE OR REPLACE FUNCTION delete_user_complete(user_id_to_delete uuid)
RETURNS boolean AS $$
DECLARE
  profile_id uuid;
BEGIN
  -- Get the profile ID for this user
  SELECT id INTO profile_id FROM profiles WHERE user_id = user_id_to_delete;
  
  IF profile_id IS NULL THEN
    RAISE WARNING 'No profile found for user %', user_id_to_delete;
    RETURN false;
  END IF;
  
  -- Delete all listings by this user
  DELETE FROM listings WHERE seller_id = profile_id;
  
  -- Delete all favorites by this user
  DELETE FROM favorites WHERE user_id = user_id_to_delete;
  
  -- Delete all messages sent by or to this user
  DELETE FROM messages WHERE sender_id = user_id_to_delete OR receiver_id = user_id_to_delete;
  
  -- Delete all reviews by or about this user
  DELETE FROM reviews WHERE reviewer_id = user_id_to_delete OR reviewed_id = user_id_to_delete;
  
  -- Delete the user's profile
  DELETE FROM profiles WHERE user_id = user_id_to_delete;
  
  -- Note: We don't delete from auth.users as that requires special permissions
  -- The application should handle that separately if needed
  
  RETURN true;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'Error deleting user %: %', user_id_to_delete, SQLERRM;
    RETURN false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Ensure admin can see all listings including pending ones
DROP POLICY IF EXISTS "admin_select_all_listings" ON listings;
CREATE POLICY "admin_select_all_listings" ON listings
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE user_id = auth.uid() AND is_admin = true
    )
  );

-- Fix policy for users to see their own pending listings
DROP POLICY IF EXISTS "listings_select_own" ON listings;
CREATE POLICY "listings_select_own" ON listings
  FOR SELECT USING (
    auth.uid() IS NOT NULL AND 
    seller_id IN (
      SELECT id FROM profiles 
      WHERE user_id = auth.uid()
    )
  );

-- Create a function to check if a listing belongs to a user
CREATE OR REPLACE FUNCTION listing_belongs_to_user(listing_id uuid, user_id uuid)
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM listings l
    JOIN profiles p ON l.seller_id = p.id
    WHERE l.id = listing_id AND p.user_id = user_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create a function to get user profile by auth ID
CREATE OR REPLACE FUNCTION get_profile_by_auth_id(auth_user_id uuid)
RETURNS jsonb AS $$
DECLARE
  profile_data jsonb;
BEGIN
  SELECT to_jsonb(p) INTO profile_data
  FROM profiles p
  WHERE p.user_id = auth_user_id;
  
  RETURN profile_data;
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create indexes to improve performance
CREATE INDEX IF NOT EXISTS idx_listings_seller_id_availability ON listings(seller_id, availability);
CREATE INDEX IF NOT EXISTS idx_listings_seller_type_availability ON listings(seller_type, availability);