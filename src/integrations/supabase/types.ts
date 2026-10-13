export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      acces: {
        Row: {
          created_at: string
          cree_par: string | null
          email: string
          expire_le: string | null
          id: string
          revoque_le: string | null
          role: Database["public"]["Enums"]["app_role"]
        }
        Insert: {
          created_at?: string
          cree_par?: string | null
          email: string
          expire_le?: string | null
          id?: string
          revoque_le?: string | null
          role: Database["public"]["Enums"]["app_role"]
        }
        Update: {
          created_at?: string
          cree_par?: string | null
          email?: string
          expire_le?: string | null
          id?: string
          revoque_le?: string | null
          role?: Database["public"]["Enums"]["app_role"]
        }
        Relationships: []
      }
      avis_controle: {
        Row: {
          created_at: string
          facture_id: string
          id: string
          message: string
          niveau: string
          source: string
        }
        Insert: {
          created_at?: string
          facture_id: string
          id?: string
          message: string
          niveau: string
          source: string
        }
        Update: {
          created_at?: string
          facture_id?: string
          id?: string
          message?: string
          niveau?: string
          source?: string
        }
        Relationships: [
          {
            foreignKeyName: "avis_controle_facture_id_fkey"
            columns: ["facture_id"]
            isOneToOne: false
            referencedRelation: "factures"
            referencedColumns: ["id"]
          },
        ]
      }
      demandes_automatisation: {
        Row: {
          created_at: string
          derniere_erreur: string | null
          id: string
          objet_id: string
          statut: string
          tentatives: number
          pris_le: string | null
          termine_le: string | null
          type: string
        }
        Insert: {
          created_at?: string
          derniere_erreur?: string | null
          id?: string
          objet_id: string
          statut?: string
          tentatives?: number
          termine_le?: string | null
          type: string
        }
        Update: {
          created_at?: string
          derniere_erreur?: string | null
          id?: string
          objet_id?: string
          statut?: string
          tentatives?: number
          termine_le?: string | null
          type?: string
        }
        Relationships: []
      }
      devis: {
        Row: {
          axonaut_client_id: string | null
          axonaut_decision_le: string | null
          axonaut_devis_id: string | null
          axonaut_lien: string | null
          axonaut_numero: string | null
          commentaire: string | null
          created_at: string
          cree_par: string | null
          decide_le: string | null
          derniere_erreur: string | null
          envoye_le: string | null
          fiche_id: string | null
          id: string
          jeton: string | null
          propose_le: string | null
          reference: string
          relu_le: string | null
          relu_par: string | null
          statut: string
          updated_at: string
        }
        Insert: {
          axonaut_client_id?: string | null
          commentaire?: string | null
          cree_par?: string | null
          fiche_id?: string | null
          id?: string
          reference?: string
          statut?: string
        }
        Update: {
          axonaut_client_id?: string | null
          commentaire?: string | null
          statut?: string
        }
        Relationships: [
          {
            foreignKeyName: "devis_fiche_id_fkey"
            columns: ["fiche_id"]
            isOneToOne: false
            referencedRelation: "fiches"
            referencedColumns: ["id"]
          },
        ]
      }
      devis_lignes: {
        Row: {
          created_at: string
          devis_id: string
          id: string
          libelle: string
          ordre: number
          piece_id: string | null
          prix_unitaire_ht: number
          quantite: number
          taux_tva: number
        }
        Insert: {
          created_at?: string
          devis_id: string
          id?: string
          libelle: string
          ordre?: number
          piece_id?: string | null
          prix_unitaire_ht?: number
          quantite?: number
          taux_tva?: number
        }
        Update: {
          libelle?: string
          ordre?: number
          piece_id?: string | null
          prix_unitaire_ht?: number
          quantite?: number
          taux_tva?: number
        }
        Relationships: [
          {
            foreignKeyName: "devis_lignes_devis_id_fkey"
            columns: ["devis_id"]
            isOneToOne: false
            referencedRelation: "devis"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "devis_lignes_piece_id_fkey"
            columns: ["piece_id"]
            isOneToOne: false
            referencedRelation: "pieces_catalogue"
            referencedColumns: ["id"]
          },
        ]
      }
      entreprises: {
        Row: {
          axonaut_client_id: string | null
          code: string
          created_at: string
          id: string
          nom: string
        }
        Insert: {
          axonaut_client_id?: string | null
          code?: string
          created_at?: string
          id?: string
          nom: string
        }
        Update: {
          axonaut_client_id?: string | null
          code?: string
          created_at?: string
          id?: string
          nom?: string
        }
        Relationships: []
      }
      evenements: {
        Row: {
          adresse: string
          code: string
          created_at: string
          cree_par: string | null
          date_intervention: string
          entreprise_id: string
          id: string
          places_max: number | null
          site: string
          statut: string
        }
        Insert: {
          adresse?: string
          code?: string
          created_at?: string
          cree_par?: string | null
          date_intervention: string
          entreprise_id: string
          id?: string
          places_max?: number | null
          site: string
          statut?: string
        }
        Update: {
          adresse?: string
          code?: string
          created_at?: string
          cree_par?: string | null
          date_intervention?: string
          entreprise_id?: string
          id?: string
          places_max?: number | null
          site?: string
          statut?: string
        }
        Relationships: [
          {
            foreignKeyName: "evenements_entreprise_id_fkey"
            columns: ["entreprise_id"]
            isOneToOne: false
            referencedRelation: "entreprises"
            referencedColumns: ["id"]
          },
        ]
      }
      facture_lignes: {
        Row: {
          facture_id: string
          id: string
          libelle: string
          ordre: number
          prix_unitaire_ht: number
          quantite: number
          taux_tva: number
        }
        Insert: {
          facture_id: string
          id?: string
          libelle: string
          ordre?: number
          prix_unitaire_ht?: number
          quantite?: number
          taux_tva?: number
        }
        Update: {
          facture_id?: string
          id?: string
          libelle?: string
          ordre?: number
          prix_unitaire_ht?: number
          quantite?: number
          taux_tva?: number
        }
        Relationships: [
          {
            foreignKeyName: "facture_lignes_facture_id_fkey"
            columns: ["facture_id"]
            isOneToOne: false
            referencedRelation: "factures"
            referencedColumns: ["id"]
          },
        ]
      }
      factures: {
        Row: {
          axonaut_facture_id: string | null
          created_at: string
          detail: string | null
          envoyee_le: string | null
          id: string
          inscription_id: string
          prete_le: string | null
          prete_par: string | null
          statut: string
          updated_at: string
          validee_le: string | null
          validee_par: string | null
        }
        Insert: {
          axonaut_facture_id?: string | null
          created_at?: string
          detail?: string | null
          envoyee_le?: string | null
          id?: string
          inscription_id: string
          prete_le?: string | null
          prete_par?: string | null
          statut?: string
          updated_at?: string
          validee_le?: string | null
          validee_par?: string | null
        }
        Update: {
          axonaut_facture_id?: string | null
          created_at?: string
          detail?: string | null
          envoyee_le?: string | null
          id?: string
          inscription_id?: string
          prete_le?: string | null
          prete_par?: string | null
          statut?: string
          updated_at?: string
          validee_le?: string | null
          validee_par?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "factures_inscription_id_fkey"
            columns: ["inscription_id"]
            isOneToOne: true
            referencedRelation: "inscriptions"
            referencedColumns: ["id"]
          },
        ]
      }
      fiche_points: {
        Row: {
          constats: string[]
          etat: string
          fiche_id: string
          groupe: string
          id: string
          point: string
          remarque: string | null
        }
        Insert: {
          constats?: string[]
          etat?: string
          fiche_id: string
          groupe: string
          id?: string
          point: string
          remarque?: string | null
        }
        Update: {
          constats?: string[]
          etat?: string
          fiche_id?: string
          groupe?: string
          id?: string
          point?: string
          remarque?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fiche_points_fiche_id_fkey"
            columns: ["fiche_id"]
            isOneToOne: false
            referencedRelation: "fiches"
            referencedColumns: ["id"]
          },
        ]
      }
      fiches: {
        Row: {
          commentaire: string | null
          debut_le: string
          id: string
          inscription_id: string
          mecanicien_id: string | null
          statut: string
          termine_le: string | null
        }
        Insert: {
          commentaire?: string | null
          debut_le?: string
          id?: string
          inscription_id: string
          mecanicien_id?: string | null
          statut?: string
          termine_le?: string | null
        }
        Update: {
          commentaire?: string | null
          debut_le?: string
          id?: string
          inscription_id?: string
          mecanicien_id?: string | null
          statut?: string
          termine_le?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fiches_inscription_id_fkey"
            columns: ["inscription_id"]
            isOneToOne: true
            referencedRelation: "inscriptions"
            referencedColumns: ["id"]
          },
        ]
      }
      inscriptions: {
        Row: {
          axonaut_client_id: string | null
          code_postal: string
          consentement_le: string
          created_at: string
          email: string
          evenement_id: string
          id: string
          nom: string
          partie_signalee: string
          prenom: string
          probleme_percu: string | null
          telephone: string
          type_velo: string
          velo_modele: string | null
        }
        Insert: {
          axonaut_client_id?: string | null
          code_postal: string
          consentement_le: string
          created_at?: string
          email: string
          evenement_id: string
          id?: string
          nom: string
          partie_signalee: string
          prenom: string
          probleme_percu?: string | null
          telephone: string
          type_velo: string
          velo_modele?: string | null
        }
        Update: {
          axonaut_client_id?: string | null
          code_postal?: string
          consentement_le?: string
          created_at?: string
          email?: string
          evenement_id?: string
          id?: string
          nom?: string
          partie_signalee?: string
          prenom?: string
          probleme_percu?: string | null
          telephone?: string
          type_velo?: string
          velo_modele?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "inscriptions_evenement_id_fkey"
            columns: ["evenement_id"]
            isOneToOne: false
            referencedRelation: "evenements"
            referencedColumns: ["id"]
          },
        ]
      }
      pieces_catalogue: {
        Row: {
          actif: boolean
          axonaut_produit_id: string | null
          id: string
          libelle: string
          prix_vente_ht: number
          reference: string
          taux_tva: number
        }
        Insert: {
          actif?: boolean
          axonaut_produit_id?: string | null
          id?: string
          libelle: string
          prix_vente_ht?: number
          reference: string
          taux_tva?: number
        }
        Update: {
          actif?: boolean
          axonaut_produit_id?: string | null
          id?: string
          libelle?: string
          prix_vente_ht?: number
          reference?: string
          taux_tva?: number
        }
        Relationships: []
      }
      pieces_posees: {
        Row: {
          a_commander: boolean
          created_at: string
          fiche_id: string
          id: string
          libelle: string
          piece_id: string | null
          prix_unitaire_ht: number
          quantite: number
        }
        Insert: {
          a_commander?: boolean
          created_at?: string
          fiche_id: string
          id?: string
          libelle: string
          piece_id?: string | null
          prix_unitaire_ht?: number
          quantite?: number
        }
        Update: {
          a_commander?: boolean
          created_at?: string
          fiche_id?: string
          id?: string
          libelle?: string
          piece_id?: string | null
          prix_unitaire_ht?: number
          quantite?: number
        }
        Relationships: [
          {
            foreignKeyName: "pieces_posees_fiche_id_fkey"
            columns: ["fiche_id"]
            isOneToOne: false
            referencedRelation: "fiches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pieces_posees_piece_id_fkey"
            columns: ["piece_id"]
            isOneToOne: false
            referencedRelation: "pieces_catalogue"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      code_court: { Args: never; Returns: string }
      controler_facture: { Args: { p_facture: string }; Returns: undefined }
      email_utilisateur: { Args: { p_user: string }; Returns: string }
      evenements_ouverts: { Args: { p_code_entreprise: string }; Returns: Json }
      has_any_role: {
        Args: { _roles: Database["public"]["Enums"]["app_role"][] }
        Returns: boolean
      }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      inscrire: { Args: { p: Json }; Returns: Json }
      mes_roles: {
        Args: never
        Returns: Database["public"]["Enums"]["app_role"][]
      }
      preparer_facture: { Args: { p_facture: string }; Returns: undefined }
      reserver_demandes: { Args: { p_limite?: number }; Returns: Json }
      ecrire_resultat: { Args: { p: Json }; Returns: Json }
      donnees_demande: { Args: { p_type: string; p_objet: string }; Returns: Json }
      terminer_fiche: { Args: { p_fiche: string }; Returns: string }
      valider_facture: { Args: { p_facture: string }; Returns: undefined }
      devis_controles: { Args: { p_devis: string }; Returns: Json }
      devis_proposer: { Args: { p_devis: string }; Returns: undefined }
      devis_preparer_envoi: { Args: { p_devis: string }; Returns: Json }
      devis_noter_envoi: { Args: { p: Json }; Returns: Json }
      devis_public: { Args: { p_jeton: string }; Returns: Json }
      devis_repondre: { Args: { p_jeton: string; p_decision: string }; Returns: Json }
      devis_noter_decision: { Args: { p: Json }; Returns: Json }
    }
    Enums: {
      app_role: "dirigeant" | "mecanicien" | "atelier"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      app_role: ["dirigeant", "mecanicien", "atelier"],
    },
  },
} as const
