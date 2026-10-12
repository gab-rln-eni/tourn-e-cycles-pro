# Tournée Cycles Pro

Crée l'application web « Tournée Cycles », en français, mobile d'abord. Tournée Cycles est un atelier mobile de réparation de vélos à Lyon qui intervient en entreprise : des journées de maintenance où les salariés font réviser leur vélo sur leur lieu de travail. L'application remplace le formulaire d'inscription, la fiche de maintenance papier et la double saisie des factures. Elle est utilisée sur téléphone, souvent les mains sales : gros boutons, choix à toucher plutôt que texte à taper.

1. PAGES (5 routes, toute autre adresse redirige vers « / »)
- « / » Accueil : logo texte « Tournée Cycles », phrase « L'atelier vélo qui vient à vous. », bouton « Se connecter » (fenêtre modale : email et mot de passe, lien « Créer un compte »). Une personne connectée est redirigée selon son rôle : dirigeant ou mécanicien vers « /journee », atelier vers « /bureau ». Une personne connectée sans accès valide voit « Votre accès n'est pas actif. Contactez Tournée Cycles. »
- « /inscription » Inscription des salariés, publique, sans compte. Un seul formulaire pour tous les sites et toutes les dates. Chaque entreprise cliente a son lien « /inscription?c=<code entreprise> » : le salarié choisit sa journée (site et date) dans la liste des journées ouvertes de son entreprise seulement ; aucune autre entreprise n'est jamais affichée. Si l'adresse contient aussi « &e=<code journée> », cette journée est présélectionnée et affichée en titre. Sans code valide : message « Utilisez le lien transmis par votre entreprise. », sans liste. Champs obligatoires, marqués comme tels : nom, prénom, téléphone, email, code postal, type de vélo (« Électrique (VAE) » ou « Musculaire »), partie du vélo qui pose problème (choix parmi Freins, Roues et pneus, Vitesses et chaîne, Direction, Cadre, Autre, Je ne sais pas), case de consentement. Champs facultatifs : marque et modèle du vélo, description libre du problème (300 caractères). Bloc d'information au dessus du bouton : « Tournée Cycles est labellisé Bonus Répar Sport & Cycle. Les informations obligatoires sont celles demandées pour en bénéficier. » Après envoi : écran « Inscription enregistrée » rappelant la journée choisie. Si la journée est complète ou close : message clair, pas d'envoi.
- « /journee » La journée (rôles dirigeant et mécanicien) : sélecteur de journée (par défaut la journée du jour, sinon la prochaine), titre entreprise, site et date, compteurs (inscrits, fiches terminées), liste des vélos inscrits en grandes cartes (prénom, nom, type de vélo, partie signalée, état de la fiche : à faire, en cours, terminée) ; toucher une carte ouvre « /fiche/$inscriptionId ». Pour le dirigeant seulement, en haut : bouton « Nouvelle journée » (fenêtre : entreprise existante ou nouvelle, site, adresse, date, nombre de places facultatif) ; après création, le lien d'inscription de l'entreprise et celui de la journée s'affichent, chacun avec un bouton « Copier le lien ».
- « /fiche/$inscriptionId » Fiche de maintenance d'un vélo (rôles dirigeant et mécanicien) : en tête le propriétaire, le vélo et le problème signalé ; puis les groupes d'organes de la section 5, chacun repliable, avec un bouton « Tout est bon » par groupe ; pour chaque point, quatre gros boutons « Bon », « À régler », « À réparer », « À changer » (Bon par défaut, l'état choisi bien visible, pas seulement par la couleur), remarque facultative. Bloc « Pièces posées » : recherche dans le catalogue (référence ou libellé), quantité avec boutons plus et moins, prix unitaire repris du catalogue et modifiable, ligne libre possible, case « À commander » si la pièce manque. Commentaire général. Enregistrement automatique à chaque changement. Bouton « Fiche terminée » (confirmation) : la fiche passe à terminée et la facture du vélo est créée au statut « à préparer ».
- « /bureau » Bureau (rôles atelier et dirigeant) : onglet « Factures » : liste par journée des factures avec leur statut (à préparer, brouillon prêt, à valider, validée, envoyée, échec) ; toucher une facture ouvre son détail : client, lignes (libellé, quantité, prix unitaire HT, montant HT, total HT, TVA 20 %, total TTC), points de la fiche qui ne sont pas « Bon », avis de contrôle (vert, orange ou rouge, avec un texte), lignes modifiables (ajouter, retirer, corriger) tant que la facture n'est pas validée, bouton « Prête à valider ». Bouton « Valider et envoyer » visible et utilisable par le dirigeant seulement, avec une fenêtre de confirmation rappelant le total TTC et le destinataire. Onglet « Tableau de bord » : par entreprise, site et date : inscrits, fiches terminées, factures validées, factures envoyées, total HT.
- En-tête commun : logo texte, liens selon le rôle (La journée, Bureau), menu du compte avec déconnexion. Pied de page commun : « Tournée Cycles, démonstration | Mentions légales | Confidentialité | Cookies », les trois textes en fenêtres modales.

2. AUTHENTIFICATION ET ACCÈS
- Connexion par email et mot de passe ; confirmation de l'email obligatoire (confirmation automatique désactivée).
- Les accès sont nominatifs et peuvent être temporaires. Table « acces » : id, email (en minuscules, unique par rôle), role (enum app_role : 'dirigeant', 'mecanicien', 'atelier'), expire_le (horodatage, vide = sans expiration), revoque_le (vide = actif), cree_par, created_at. Insérer d'office l'accès dirigeant, sans expiration, pour gabriel.roulon@gmail.com.
- Fonction has_role(_user_id uuid, _role app_role) en security definer, search_path fixé : vrai seulement si l'email de l'utilisateur est confirmé et qu'un accès de ce rôle existe pour cet email, non révoqué et non expiré. Toutes les règles RLS et toutes les pages passent par has_role, l'expiration agit donc immédiatement. Aucune colonne de rôle ailleurs. La table acces n'a pas d'écran : elle est remplie et modifiée seulement par SQL (jeu de démonstration) ; le dirigeant la lit, personne ne l'écrit depuis l'interface.

3. TABLES (RLS sur toutes ; noms de colonnes en français sans accent)
- entreprises : id, nom, code (texte court unique et non devinable, généré à la création, sert au lien ?c=), axonaut_client_id (texte, vide possible), created_at.
- evenements : id, entreprise_id, site, adresse, date_intervention (date), places_max (vide possible), statut ('ouvert', 'clos'), code (texte court unique, généré à la création, sert au lien &e=), cree_par, created_at.
- inscriptions : id, evenement_id, nom, prenom, telephone, email, code_postal, type_velo ('vae', 'musculaire'), velo_modele, partie_signalee ('freins', 'roues', 'transmission', 'direction', 'cadre', 'autre', 'inconnu'), probleme_percu, consentement_le, axonaut_client_id (vide possible), created_at. Une inscription correspond à un vélo et à son propriétaire.
- fiches : id, inscription_id (unique), mecanicien_id, statut ('en_cours', 'terminee'), commentaire, debut_le, termine_le.
- fiche_points : id, fiche_id, groupe, point, etat ('bon', 'a_regler', 'a_reparer', 'a_changer'), constats (tableau de texte, pour les points à constats), remarque ; unique (fiche_id, groupe, point). Seuls les points qui ne sont pas « Bon » ou qui portent une remarque ou un constat sont enregistrés.
- pieces_catalogue : id, reference, libelle, prix_vente_ht (numérique), taux_tva (défaut 20), axonaut_produit_id (vide possible), actif.
- pieces_posees : id, fiche_id, piece_id (vide pour une ligne libre), libelle, quantite, prix_unitaire_ht, a_commander (booléen), created_at.
- factures : id, inscription_id (unique), statut ('a_preparer', 'brouillon', 'a_valider', 'validee', 'envoyee', 'echec'), axonaut_facture_id, prete_par, prete_le, validee_par, validee_le, envoyee_le, detail, created_at, updated_at.
- facture_lignes : id, facture_id, libelle, quantite, prix_unitaire_ht, taux_tva, ordre. À la création de la facture, les lignes sont copiées des pièces posées ; elles se corrigent ensuite ici.
- avis_controle : id, facture_id, source ('regles', 'ia'), niveau ('ok', 'attention', 'erreur'), message, created_at.
- demandes_automatisation : id, type ('client', 'commande', 'brouillon', 'controle', 'envoi'), objet_id (uuid), statut ('a_faire', 'en_cours', 'fait', 'echec'), tentatives (défaut 0), derniere_erreur, created_at, termine_le. Lecture : dirigeant et atelier ; écriture seulement par les fonctions SQL ci-dessous.
Traçabilité sans table de journal : chaque table métier garde qui a agi et quand (evenements.cree_par et created_at, fiches.mecanicien_id, debut_le et termine_le, factures.prete_par, prete_le, validee_par et validee_le) ; ces noms et dates s'affichent là où l'on travaille.
Droits : mécanicien et dirigeant lisent journées et inscriptions et écrivent fiches, fiche_points et pieces_posees ; atelier et dirigeant lisent tout et écrivent factures et facture_lignes ; seul le dirigeant crée les journées et passe une facture à « validee ». Aucune règle RLS pour les visiteurs non connectés.

4. FONCTIONS SQL (security definer, search_path fixé)
- evenements_ouverts(p_code_entreprise text) exécutable par anon : nom de l'entreprise, puis id, site, date_intervention, code, complet (booléen) des journées ouvertes de cette entreprise seulement, datées d'aujourd'hui ou plus tard, triées par date ; rien si le code est inconnu.
- inscrire(p jsonb) exécutable par anon : contrôle tous les champs obligatoires (email au bon format, code postal à 5 chiffres, téléphone de 10 chiffres, consentement vrai, journée ouverte et non complète, longueurs bornées), insère l'inscription, puis insère une demande_automatisation « a_faire » de type 'client', objet = l'inscription. Erreur claire en français sinon.
- terminer_fiche(p_fiche uuid) : passe la fiche à terminée, crée la facture « a_preparer » et ses lignes, insère une demande 'brouillon' ; si une pièce posée est « à commander », insère aussi une demande 'commande' (objet = la journée).
- controler_facture(p_facture uuid) : contrôles simples, sans IA, écrits dans avis_controle avec source 'regles' (remplace les avis 'regles' précédents) : facture sans ligne ; prix unitaire qui s'écarte de plus de 20 % du prix catalogue ; point « À changer » sans aucune pièce posée ; email du client absent. Appelée à l'ouverture du détail et à chaque correction.
- valider_facture(p_facture uuid) : dirigeant seulement, facture « a_valider » seulement ; passe à « validee », écrit validee_par et validee_le, insère une demande 'envoi'.

5. FICHE DE MAINTENANCE (reprend la fiche papier de Tournée Cycles ; groupes dans cet ordre)
- Roue avant : Serrage, Centrage, Voile, Moyeu, Position de la valve, Sens de rotation du pneu, Usure du pneu, Pression, Tension des rayons, État des rayons ; point à constats « Surface de freinage de la jante » (Usée, Chocs, Rayures, Graisse).
- Roue arrière : mêmes points que la roue avant.
- Cadre : Cadre, Fourche.
- Frein avant : Efficacité, Serrage de l'étrier, État de l'étrier, Patins ou plaquettes, Usure, Position, Serrage.
- Frein arrière : mêmes points que le frein avant.
- Câblerie : Câble de frein avant, Gaine de frein avant, Câble de frein arrière, Gaine de frein arrière, Levier de frein gauche, Levier de frein droit ; points à constats « Disque avant » et « Disque arrière » (Usé, Voile, Graisse, Choc).
- Direction : Jeu de direction (serrage), Jeu de direction (rotation et roulements), Cintre, Cintre (serrage), Cintre (position), Potence, Potence (serrage), Enfoncement du plongeur, Poignées ou ruban.
- Transmission : Manette gauche, Manette droite, Câble gauche, Gaine gauche, Câble droit, Gaine droite, Dérailleur avant (état), Dérailleur avant (position), Dérailleur avant (fonctionnement), Pédalier, Plateaux, Boîtier de pédalier, Boîtier de pédalier (serrage), Chaîne, Dérailleur arrière (état), Dérailleur arrière (position), Dérailleur arrière (fonctionnement), Cassette, Patte de dérailleur.
- Position : Tige de selle, Selle, Pédales.
Les points à constats affichent des cases à cocher au lieu de l'échelle à quatre états. Le référentiel des points est une constante du code, pas une table.

6. STYLE (charte Tournée Cycles)
- Fond crème #F5F0E0, cartes blanches, texte principal #1F2A30. Couleur principale bleu #007A9B pour les boutons principaux (texte blanc) et les grands titres ; pour un texte bleu de petite taille sur fond crème, utiliser #006480. Couleur d'accent rose #DB5061 pour les aplats, pastilles et alertes seulement, jamais pour du texte courant ; texte rose de petite taille : #B83246.
- Police libre très lisible « Atkinson Hyperlegible » (Google Fonts) pour tout le texte, en gras pour les titres.
- Mobile d'abord : zones tactiles d'au moins 48 px, boutons pleine largeur sur téléphone, contrastes forts, aucune action importante cachée dans un menu. Les états ne sont jamais portés par la couleur seule (texte ou icône en plus).
- Textes en français simple, sans jargon technique, sans tiret long ni demi-cadratin.

7. DONNÉES D'EXEMPLE
Aucune personne fictive. Insère seulement le catalogue de pièces suivant (prix de vente HT, TVA 20 %) : « Câble de frein inox 1,6 mm 1,80 m » 2,08 ; « Gaine de frein 5 mm » 2,08 ; « Main d'oeuvre (heure) » 50,00 ; « Marquage vélo » 16,67.

8. CONFORMITÉ (cadre indicatif, non validé juridiquement)
- Accessibilité : viser WCAG 2.1 niveau AA (référence RGAA) : contrastes, navigation au clavier, focus visible, libellés de formulaires, messages d'erreur reliés aux champs, hiérarchie de titres, attribut lang="fr".
- Mentions légales : éditeur « Tournée Cycles, application de démonstration » ; hébergeur : à compléter.
- Confidentialité : données traitées à l'inscription (nom, prénom, téléphone, email, code postal, vélo, problème signalé) ; finalités : organiser la journée, réaliser la maintenance, établir la facture, bénéficier du label Bonus Répar Sport & Cycle ; les données ne sont pas réutilisées à d'autres fins ; droits d'accès, de rectification et de suppression auprès de Tournée Cycles.
- Cookies : uniquement ce qui est strictement nécessaire à la connexion, pas de bandeau, aucune mesure d'audience ni traceur tiers.

This project was built with [Lovable](https://lovable.dev).

## Build with Lovable

Continue developing this project in the [Lovable editor](https://lovable.dev/projects/3e4adbfd-0017-4a27-96fd-b3716aed7962).

- **Ship faster**: describe what you want to build and Lovable handles the code.
- **Stay in sync**: every change made in Lovable is committed straight to this repository.
- **Full ownership**: this code is yours. Push to `main` on GitHub and your changes sync back into Lovable, ready for your next prompt.

## Development

Prefer working locally? You need Node.js and npm — [install with nvm](https://github.com/nvm-sh/nvm#installing-and-updating).

```sh
git clone <this-repository-url>
cd <repository-name>
npm i
npm run dev
```
