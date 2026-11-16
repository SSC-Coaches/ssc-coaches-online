# Super Summer Camp – Coaches Online

Eine **deploybare Web-App** (keine reine Offline-Demo) mit persönlichem E-Mail-Login, Coach- und Administrator-Portal, zentraler Supabase-Datenbank, CHF-Stundenansätzen und Excel-Export. Die App **ist noch nicht online**: Für den Betrieb sind Supabase und Hosting einmalig einzurichten.

## Funktionen

- E-Mail-/Passwort-Login über Supabase Auth; Zurücksetzen des Passworts
- Coach sieht ausschliesslich eigene Zeiteinträge; Admin sieht alle Einträge
- Datum, Beginn, Ende, Pause, Lehrgang, Art (Kurs/Privat/Off-Ice/Sonstiges), Bemerkung
- Automatische Berechnung von Stunden, Ansatz und Betrag in der Datenbank (CHF)
- Admin kann Einträge von allen Coaches ansehen, bearbeiten und löschen
- Admin kann individuelle Ansätze der Coaches und deren Aktiv-Status setzen
- XLSX-Export aller sichtbaren/gefilterten Einträge, plus Zusammenfassung pro Coach
- Audit-Protokoll für Zeit-Einträge; Datenzugriff über Row Level Security
- Responsive für PC, Tablet und Smartphone

## 1. Supabase einrichten

1. Unter https://supabase.com ein neues Projekt erstellen.
2. Unter **SQL Editor** die komplette Datei `supabase/schema.sql` ausführen.
3. Unter **Authentication > Providers > Email** E-Mail-Login aktivieren und **öffentliche Registrierung deaktivieren**, damit die Camp-Leitung die Konten kontrolliert.
4. Unter **Authentication > Users** über **Invite user** zuerst die eigene E-Mail-Adresse einladen. Den Einladungslink bestätigen, ein Passwort vergeben und die **User UUID** kopieren.
5. Im SQL Editor **einmalig** (UUID ersetzen) ausführen:

   ```sql
   update public.profiles
   set role = 'admin', full_name = 'Camp-Leitung'
   where id = 'DEINE-USER-UUID';
   ```

6. Weitere Trainer über **Authentication > Users > Invite user** einladen. Ihre Konten werden automatisch als `coach` erstellt. Als Administratorin im Portal die Stundenansätze hinterlegen.
7. Unter **Project Settings > API** die **Project URL** und den **Publishable Key** (bei älteren Projekten `anon` key) kopieren. **Niemals `service_role` oder Secret API Key in die Web-App einfügen!**
8. Unter **Authentication > URL Configuration** die spätere Web-Adresse als Site URL und Redirect URL hinzufügen (Passwort-Reset).

> Hinweis: Die Erstellung der Benutzer findet aus Sicherheitsgründen im Supabase Dashboard statt. Im SSC-Portal ist sie aktuell nicht enthalten.

## 2. Lokal testen

Node.js 20+ installieren, dann im Projektordner:

```bash
npm install
cp .env.example .env
# In .env die eigenen Supabase-Werte einsetzen
npm run dev
```

Die Terminal-Anzeige zeigt die lokale Webadresse (typischerweise http://localhost:5173).

## 3. Online veröffentlichen (z. B. Vercel)

1. Projektordner in ein **privates GitHub-Repository** hochladen.
2. Bei https://vercel.com neues Projekt über das Repository importieren (Framework Vite).
3. In den Projekt-Einstellungen die Environment Variables `VITE_SUPABASE_URL` und `VITE_SUPABASE_ANON_KEY` setzen.
4. Deployment starten und die Webadresse in Supabase Auth URL Configuration hinterlegen.
5. Zugriffsregeln mit einem Coach-Testkonto und einem Admin-Testkonto sorgfältig testen.

## Sicherheits- und Betriebsnotizen

- Die **RLS-Richtlinien in der SQL-Datei sind unverzichtbar**. Ohne sie nicht produktiv einsetzen.
- Der `anon`/Publishable Key ist ein öffentlicher Client-Schlüssel; Auth und RLS schützen die Daten. Den `service_role` Key niemals im Browser verwenden.
- **Admin-Rollen dürfen ausschliesslich im Supabase SQL Editor oder mit einem sicheren Backend vergeben werden.** Coaches dürfen ihre Rolle nicht ändern.
- Rates: Bei Erstellung wird der jeweilige Stundenansatz als Snapshot gespeichert. Geänderte Ansätze wirken für neue Einträge. Bei Änderung von Coach, Trainingsart, Beginn, Ende oder Pause eines bestehenden Eintrags wird der aktuelle Ansatz angewandt.
- Kein Freigabe-Workflow auf Wunsch: Einträge sind nach Speicherung sofort für die Administratorin sichtbar. Coaches können ihre Einträge bearbeiten oder löschen; Änderungen werden protokolliert.
- Zeiterfassung: Ende muss am selben Tag nach Beginn liegen. Nachtschichten werden in dieser Version nicht unterstützt.
- Das Audit-Protokoll erfasst Änderungen an Zeiteinträgen, **nicht** an Profil-Stundenansätzen.
- Das Dashboard lädt maximal 5’000 Einträge. Für umfangreichere Nutzung Pagination und einen serverseitigen vollständigen Export ergänzen.
- Vor echtem Einsatz: Schweizer Datenschutz, Zugriffsschutz der Geräte, Aufbewahrung, Backup, Löschkonzept, Prozess für Abschluss/Archivierung der Abrechnungen und geeignete Hosting-/Datenspeicherregion prüfen.
- Excel-Export wird im Browser lokal erstellt. Das Paket `xlsx` aus npm Version 0.18.x sollte vor einem produktiven Go-live auf Wartung/Sicherheitsstand geprüft oder durch ein gepflegtes XLSX-Paket ersetzt werden.

## Erweiterungsideen

Separate Wochenfilter, Schweizer Feiertage, Pauschalen/Spesen, Coach-Datenpflege, PDF-Abrechnungen, zeitliche Sperrung nach Abrechnung, Erinnerungen für fehlende Einträge, sichere Einladungen direkt über ein Admin-Backend.
