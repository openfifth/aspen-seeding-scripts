-- Aspen Discovery: Event Mock Data Script (Idempotent & Registration Enabled)
-- AI-generated, human-tested seeding scripts. DEV USE ONLY
-- VERSION: 3.1.0
-- Targets: MariaDB on aspen-db container

START TRANSACTION;

SET @libraryId = 8;
SET @locationId = 8;

-- 0. Enable Events Module globally
UPDATE modules SET enabled = 1 WHERE name = 'Events';

-- 0a. Enable Events for ALL Libraries
UPDATE library SET aspenEventsToInclude = 1;

-- 0b. Enable Event Registration for ALL Libraries (if column exists)
SET @hasAllowEventRegistration = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'library' AND COLUMN_NAME = 'allowEventRegistration'
);
SET @sql = IF(@hasAllowEventRegistration > 0, 'UPDATE library SET allowEventRegistration = 1', 'SELECT 1');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 0c. Create Events Indexing Settings
INSERT INTO events_indexing_settings (name, numberOfDaysToIndex, runFullUpdate)
VALUES ('Default', 365, 1)
ON DUPLICATE KEY UPDATE runFullUpdate = 1;

-- 0c. Create Aspen Event Settings
INSERT IGNORE INTO aspen_event_settings (name, registrationModalBody)
VALUES ('Default', 'Please complete the registration form below.');

-- 0d. Link ALL Libraries to Aspen Event Settings
INSERT INTO library_events_setting (settingSource, settingId, libraryId, eventsFacetSettingsId)
SELECT 'aspenEvents', s.id, l.libraryId, 1
FROM aspen_event_settings s, library l
WHERE s.name = 'Default'
AND NOT EXISTS (
    SELECT 1 FROM library_events_setting
    WHERE settingSource = 'aspenEvents' AND settingId = s.id AND libraryId = l.libraryId
);

-- 0e. Link ALL Libraries to Events Facet Groups
INSERT INTO library_events_facet_setting (libraryId, eventsFacetGroupId)
SELECT l.libraryId, 1 FROM library l
WHERE NOT EXISTS (
    SELECT 1 FROM library_events_facet_setting
    WHERE libraryId = l.libraryId AND eventsFacetGroupId = 1
);

-- ============================================================
-- Detect optional columns (schema varies by version/branch)
-- ============================================================

-- event_field.fieldUse (added in DIS-1597 registration branch)
--   1 = Event description section  |  2 = Event registration form
SET @hasFieldUse = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event_field' AND COLUMN_NAME = 'fieldUse'
);

-- event_field_set.fieldSetUse (added in DIS-1597 registration branch)
--   1 = Event description section  |  2 = Event registration form
SET @hasFieldSetUse = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event_field_set' AND COLUMN_NAME = 'fieldSetUse'
);

-- event_type.eventRegistrationFieldSetId (added in DIS-1597 alongside rename of eventFieldSetId)
SET @hasRegFieldSetId = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event_type' AND COLUMN_NAME = 'eventRegistrationFieldSetId'
);

-- Registration columns (added via aspen_event_registration_updates)
SET @hasRegRequired = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND COLUMN_NAME = 'registrationRequired'
);
SET @hasEventSeats = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND COLUMN_NAME = 'numberOfSeats'
);
SET @hasInstanceSeats = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event_instance' AND COLUMN_NAME = 'numberOfSeats'
);

-- Waitlist columns (added in DIS-1715 waiting list branch)
SET @hasWaitingList = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND COLUMN_NAME = 'waitingList'
);
SET @hasWaitingListSeats = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND COLUMN_NAME = 'waitingListNumberOfSeats'
);
SET @hasInstanceWaitingList = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event_instance' AND COLUMN_NAME = 'waitingList'
);
SET @hasInstanceWaitingListSeats = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event_instance' AND COLUMN_NAME = 'waitingListNumberOfSeats'
);

-- ============================================================
-- 1. Create Fields
-- Covers all field types (0–5) and both fieldUse values
--   type: 0=Text, 1=TextArea, 2=Checkbox, 3=SelectList, 4=Email, 5=URL
--   facetName: 0=None, 1=Age Group, 2=Program Type, 3=Category, 4=Event Type
-- ============================================================
INSERT IGNORE INTO event_field (name, description, type, allowableValues, facetName) VALUES
-- fieldUse=1: Event description fields (browsable/faceted)
('Primary Topic',        'The main theme of the event',               3, 'Crafts\nTechnology\nReading\nScience\nOutreach', 3),
('Target Age',           'Who is this event for?',                    3, 'Toddlers\nKids\nTeens\nAdults\nSeniors',         1),
('Program Type',         'Classification of the program format',      3, 'Lecture\nWorkshop\nStorytime\nDrop-in\nClub',    2),
('Speaker Name',         'Guest speaker or facilitator',              0, '', 0),
('Equipment Provided',   'Is any equipment provided to attendees?',   2, '', 0),
('Accessible',           'Is this event fully accessible?',           2, '', 0),
('Special Instructions', 'Additional prep info or notes for attendees', 1, '', 0),
('Resource Link',        'URL for supplementary event resources',     5, '', 0),
-- fieldUse=2: Registration form fields (patron-facing, captured at signup)
('Emergency Contact',    'Phone number for emergencies',              0, '', 0),
('Registration Email',   'Contact email for registration inquiries',  4, '', 0);

-- Set fieldUse on fields if the column exists
SET @setFieldUseDesc = IF(@hasFieldUse > 0,
    'UPDATE event_field SET fieldUse = 1 WHERE name IN (''Primary Topic'', ''Target Age'', ''Program Type'', ''Speaker Name'', ''Equipment Provided'', ''Accessible'', ''Special Instructions'', ''Resource Link'')',
    'SELECT ''fieldUse column not present, skipping'' AS info'
);
PREPARE stmt FROM @setFieldUseDesc; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @setFieldUseReg = IF(@hasFieldUse > 0,
    'UPDATE event_field SET fieldUse = 2 WHERE name IN (''Emergency Contact'', ''Registration Email'')',
    'SELECT ''fieldUse column not present, skipping'' AS info'
);
PREPARE stmt FROM @setFieldUseReg; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ============================================================
-- 2. Create Field Sets with distinct uses
-- fieldSetUse=1: Event description section
-- fieldSetUse=2: Event registration form
-- ============================================================
INSERT IGNORE INTO event_field_set (name) VALUES
('Standard Event Info'),   -- Topic/age/type — general browsable description
('Lecture Info'),          -- Adds speaker + equipment to standard info
('Workshop Details'),      -- Accessibility, instructions, resource link, equipment
('Registration Form');     -- Patron-facing signup fields

-- Set fieldSetUse if the column exists
SET @setFSUseDesc = IF(@hasFieldSetUse > 0,
    'UPDATE event_field_set SET fieldSetUse = 1 WHERE name IN (''Standard Event Info'', ''Lecture Info'', ''Workshop Details'')',
    'SELECT ''fieldSetUse column not present, skipping'' AS info'
);
PREPARE stmt FROM @setFSUseDesc; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @setFSUseReg = IF(@hasFieldSetUse > 0,
    'UPDATE event_field_set SET fieldSetUse = 2 WHERE name = ''Registration Form''',
    'SELECT ''fieldSetUse column not present, skipping'' AS info'
);
PREPARE stmt FROM @setFSUseReg; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ============================================================
-- 3. Link Fields to Sets
-- ============================================================
-- Standard Event Info: faceted topic/age/type fields
INSERT INTO event_field_set_field (eventFieldId, eventFieldSetId)
SELECT f.id, s.id FROM event_field f, event_field_set s
WHERE s.name = 'Standard Event Info' AND f.name IN ('Primary Topic', 'Target Age', 'Program Type')
AND NOT EXISTS (SELECT 1 FROM event_field_set_field WHERE eventFieldId = f.id AND eventFieldSetId = s.id);

-- Lecture Info: topic, age, program type, speaker name, equipment provided
INSERT INTO event_field_set_field (eventFieldId, eventFieldSetId)
SELECT f.id, s.id FROM event_field f, event_field_set s
WHERE s.name = 'Lecture Info' AND f.name IN ('Primary Topic', 'Target Age', 'Program Type', 'Speaker Name', 'Equipment Provided')
AND NOT EXISTS (SELECT 1 FROM event_field_set_field WHERE eventFieldId = f.id AND eventFieldSetId = s.id);

-- Workshop Details: topic, age, type, instructions (textarea), equipment (checkbox), accessible (checkbox), resource link (URL)
INSERT INTO event_field_set_field (eventFieldId, eventFieldSetId)
SELECT f.id, s.id FROM event_field f, event_field_set s
WHERE s.name = 'Workshop Details' AND f.name IN ('Primary Topic', 'Target Age', 'Program Type', 'Equipment Provided', 'Accessible', 'Special Instructions', 'Resource Link')
AND NOT EXISTS (SELECT 1 FROM event_field_set_field WHERE eventFieldId = f.id AND eventFieldSetId = s.id);

-- Registration Form: emergency contact (text) + registration email (email)
INSERT INTO event_field_set_field (eventFieldId, eventFieldSetId)
SELECT f.id, s.id FROM event_field f, event_field_set s
WHERE s.name = 'Registration Form' AND f.name IN ('Emergency Contact', 'Registration Email')
AND NOT EXISTS (SELECT 1 FROM event_field_set_field WHERE eventFieldId = f.id AND eventFieldSetId = s.id);

-- ============================================================
-- 4. Create Event Types (linked to field sets)
-- ============================================================
SET @standardInfoId = (SELECT id FROM event_field_set WHERE name = 'Standard Event Info');
SET @lectureInfoId   = (SELECT id FROM event_field_set WHERE name = 'Lecture Info');
SET @workshopInfoId  = (SELECT id FROM event_field_set WHERE name = 'Workshop Details');
SET @regFormId       = (SELECT id FROM event_field_set WHERE name = 'Registration Form');

-- Verify required field sets exist before proceeding
SELECT IF(@standardInfoId IS NULL OR @lectureInfoId IS NULL OR @workshopInfoId IS NULL OR @regFormId IS NULL,
    (SELECT CONCAT('Missing required field sets: ',
        IF(@standardInfoId IS NULL, 'Standard Event Info ', ''),
        IF(@lectureInfoId   IS NULL, 'Lecture Info ', ''),
        IF(@workshopInfoId  IS NULL, 'Workshop Details ', ''),
        IF(@regFormId       IS NULL, 'Registration Form ', ''))
    FROM (SELECT 1) t WHERE 1=0),
    'OK') AS field_set_check;

-- Determine which information field set column exists (schema varies between versions)
-- DIS-1597 renamed eventFieldSetId → eventInformationFieldSetId
SET @fieldSetCol = (
    SELECT COLUMN_NAME FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'event_type'
    AND COLUMN_NAME IN ('eventFieldSetId', 'eventInformationFieldSetId')
    LIMIT 1
);

-- Build and execute dynamic INSERT based on schema
-- eventLength in event_type is in hours (float)
SET @sql = CONCAT(
    'INSERT IGNORE INTO event_type (', @fieldSetCol, ', title, description, eventLength, titleCustomizable, descriptionCustomizable, lengthCustomizable) VALUES ',
    '(', @standardInfoId, ', ''Storytime'',             ''Weekly reading and fun for little ones.'',        0.5, 1, 1, 1),',
    '(', @lectureInfoId,  ', ''Library Lecture Series'', ''Academic and professional talks.'',              1.0, 1, 1, 1),',
    '(', @standardInfoId, ', ''Tech Help'',              ''Drop-in tech assistance.'',                      1.0, 1, 1, 1),',
    '(', @workshopInfoId, ', ''Workshop'',               ''Hands-on creative sessions.'',                   2.0, 1, 1, 1),',
    '(', @regFormId,      ', ''Registered Program'',     ''Program requiring advance registration.'',       1.5, 1, 1, 1)'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Link eventRegistrationFieldSetId on types that use the Registration Form field set
-- (only applies when column exists — DIS-1597 branch)
-- For 'Registered Program' its information field set IS the Registration Form, so link the
-- description types (Storytime, Workshop, etc.) to a reg form set if the column is present.
SET @linkRegFieldSet = IF(@hasRegFieldSetId > 0,
    CONCAT('UPDATE event_type SET eventRegistrationFieldSetId = ', @regFormId,
           ' WHERE title IN (''Storytime'', ''Library Lecture Series'', ''Tech Help'', ''Workshop'', ''Registered Program'')'),
    'SELECT ''eventRegistrationFieldSetId column not present, skipping'' AS info'
);
PREPARE stmt FROM @linkRegFieldSet; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ============================================================
-- 5. Link Event Types to ALL Libraries and Locations
-- ============================================================
INSERT INTO event_type_library (eventTypeId, libraryId)
SELECT t.id, l.libraryId FROM event_type t, library l
WHERE NOT EXISTS (SELECT 1 FROM event_type_library WHERE eventTypeId = t.id AND libraryId = l.libraryId);

INSERT INTO event_type_location (eventTypeId, locationId)
SELECT t.id, loc.locationId FROM event_type t, location loc
WHERE NOT EXISTS (SELECT 1 FROM event_type_location WHERE eventTypeId = t.id AND locationId = loc.locationId);

-- ============================================================
-- 6. Create Events
-- eventLength in event table is in minutes (int)
-- ============================================================
SET @storytimeTypeId  = (SELECT id FROM event_type WHERE title = 'Storytime');
SET @lectureTypeId    = (SELECT id FROM event_type WHERE title = 'Library Lecture Series');
SET @workshopTypeId   = (SELECT id FROM event_type WHERE title = 'Workshop');
SET @techHelpTypeId   = (SELECT id FROM event_type WHERE title = 'Tech Help');
SET @registeredTypeId = (SELECT id FROM event_type WHERE title = 'Registered Program');

-- Events spread across the next ~3 weeks (relative to CURDATE)
INSERT IGNORE INTO event (eventTypeId, locationId, title, description, startDate, startTime, eventLength, recurrenceOption, recurrenceCount, private) VALUES
-- No registration
(@storytimeTypeId,  @locationId, 'Toddler Storytime (Weekly)',   'Join us every Monday morning!',                   CURDATE(),                            '10:00:00', 30,  3, 4, 0),
(@techHelpTypeId,   @locationId, 'Drop-in Device Help',          'Bring your phones and tablets.',                  DATE_ADD(CURDATE(), INTERVAL 1 DAY),  '14:00:00', 120, 1, 1, 0),
(@lectureTypeId,    @locationId, 'History of Local Libraries',   'A deep dive into our past.',                      DATE_ADD(CURDATE(), INTERVAL 2 DAY),  '18:30:00', 60,  1, 1, 0),
(@workshopTypeId,   @locationId, 'Adult Book Club',              'Discussing this months bestseller.',              DATE_ADD(CURDATE(), INTERVAL 4 DAY),  '19:00:00', 90,  4, 1, 0),
-- Registration enabled, no seat cap
(@workshopTypeId,   @locationId, 'Maker Saturday: 3D Printing',  'Learn the basics of CAD and printing.',           DATE_ADD(CURDATE(), INTERVAL 6 DAY),  '13:00:00', 120, 1, 1, 0),
-- Registration + seats + waitingList + waitingListNumberOfSeats
(@registeredTypeId, @locationId, 'Intro to Genealogy Research',  'Learn to trace your family history online.',      DATE_ADD(CURDATE(), INTERVAL 8 DAY),  '10:00:00', 90,  3, 3, 0),
-- Registration + seats + waitingList (unlimited waitlist)
(@registeredTypeId, @locationId, 'Digital Photography Workshop', 'Hands-on session with DSLR and phone cameras.',   DATE_ADD(CURDATE(), INTERVAL 10 DAY), '09:00:00', 120, 1, 1, 0);

-- ============================================================
-- 7. Set registration, seats, and waitlist columns where schema supports it
-- ============================================================

-- Enable registration for 3 events (not all of them)
SET @setReg = IF(@hasRegRequired > 0,
    'UPDATE event SET registrationRequired = 1 WHERE title IN (''Maker Saturday: 3D Printing'', ''Intro to Genealogy Research'', ''Digital Photography Workshop'')',
    'SELECT ''registrationRequired column not present, skipping'' AS info'
);
PREPARE stmt FROM @setReg; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Seat limits for 2 of the 3 registered events (Maker Saturday left as unlimited)
SET @setSeats = IF(@hasEventSeats > 0,
    'UPDATE event SET numberOfSeats = 20 WHERE title IN (''Intro to Genealogy Research'', ''Digital Photography Workshop'')',
    'SELECT ''numberOfSeats (event) column not present, skipping'' AS info'
);
PREPARE stmt FROM @setSeats; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Enable waitlist for the 2 events that have seat limits
SET @setWaitingList = IF(@hasWaitingList > 0,
    'UPDATE event SET waitingList = 1 WHERE title IN (''Intro to Genealogy Research'', ''Digital Photography Workshop'')',
    'SELECT ''waitingList column not present, skipping'' AS info'
);
PREPARE stmt FROM @setWaitingList; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Waitlist seat cap for Genealogy only (Photography has unlimited waitlist)
SET @setWaitingListSeats = IF(@hasWaitingListSeats > 0,
    'UPDATE event SET waitingListNumberOfSeats = 10 WHERE title = ''Intro to Genealogy Research''',
    'SELECT ''waitingListNumberOfSeats column not present, skipping'' AS info'
);
PREPARE stmt FROM @setWaitingListSeats; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ============================================================
-- 8. Create Event Instances (multiple per event, spread across next ~3 weeks)
-- ============================================================

-- Toddler Storytime: 4 weekly instances (recurring Monday series)
INSERT INTO event_instance (eventId, date, time, length)
SELECT id, CURDATE(), '10:00:00', 30 FROM event e WHERE title = 'Toddler Storytime (Weekly)'
    AND NOT EXISTS (SELECT 1 FROM event_instance WHERE eventId = e.id AND date = CURDATE())
UNION ALL
SELECT id, DATE_ADD(CURDATE(), INTERVAL 7 DAY), '10:00:00', 30 FROM event e WHERE title = 'Toddler Storytime (Weekly)'
    AND NOT EXISTS (SELECT 1 FROM event_instance WHERE eventId = e.id AND date = DATE_ADD(CURDATE(), INTERVAL 7 DAY))
UNION ALL
SELECT id, DATE_ADD(CURDATE(), INTERVAL 14 DAY), '10:00:00', 30 FROM event e WHERE title = 'Toddler Storytime (Weekly)'
    AND NOT EXISTS (SELECT 1 FROM event_instance WHERE eventId = e.id AND date = DATE_ADD(CURDATE(), INTERVAL 14 DAY))
UNION ALL
SELECT id, DATE_ADD(CURDATE(), INTERVAL 21 DAY), '10:00:00', 30 FROM event e WHERE title = 'Toddler Storytime (Weekly)'
    AND NOT EXISTS (SELECT 1 FROM event_instance WHERE eventId = e.id AND date = DATE_ADD(CURDATE(), INTERVAL 21 DAY));

-- Drop-in Device Help: 2 sessions (Day 1 and Day 8)
INSERT INTO event_instance (eventId, date, time, length)
SELECT id, DATE_ADD(CURDATE(), INTERVAL 1 DAY), '14:00:00', 120 FROM event e WHERE title = 'Drop-in Device Help'
    AND NOT EXISTS (SELECT 1 FROM event_instance WHERE eventId = e.id AND date = DATE_ADD(CURDATE(), INTERVAL 1 DAY))
UNION ALL
SELECT id, DATE_ADD(CURDATE(), INTERVAL 8 DAY), '14:00:00', 120 FROM event e WHERE title = 'Drop-in Device Help'
    AND NOT EXISTS (SELECT 1 FROM event_instance WHERE eventId = e.id AND date = DATE_ADD(CURDATE(), INTERVAL 8 DAY));

-- History of Local Libraries: single instance (one-off lecture)
INSERT INTO event_instance (eventId, date, time, length)
SELECT id, DATE_ADD(CURDATE(), INTERVAL 2 DAY), '18:30:00', 60 FROM event e WHERE title = 'History of Local Libraries'
    AND NOT EXISTS (SELECT 1 FROM event_instance WHERE eventId = e.id AND date = DATE_ADD(CURDATE(), INTERVAL 2 DAY));

-- Adult Book Club: 3 monthly sessions
INSERT INTO event_instance (eventId, date, time, length)
SELECT id, DATE_ADD(CURDATE(), INTERVAL 4 DAY), '19:00:00', 90 FROM event e WHERE title = 'Adult Book Club'
    AND NOT EXISTS (SELECT 1 FROM event_instance WHERE eventId = e.id AND date = DATE_ADD(CURDATE(), INTERVAL 4 DAY))
UNION ALL
SELECT id, DATE_ADD(CURDATE(), INTERVAL 11 DAY), '19:00:00', 90 FROM event e WHERE title = 'Adult Book Club'
    AND NOT EXISTS (SELECT 1 FROM event_instance WHERE eventId = e.id AND date = DATE_ADD(CURDATE(), INTERVAL 11 DAY))
UNION ALL
SELECT id, DATE_ADD(CURDATE(), INTERVAL 18 DAY), '19:00:00', 90 FROM event e WHERE title = 'Adult Book Club'
    AND NOT EXISTS (SELECT 1 FROM event_instance WHERE eventId = e.id AND date = DATE_ADD(CURDATE(), INTERVAL 18 DAY));

-- Maker Saturday: 3D Printing: 2 sessions (registered, no seat cap)
INSERT INTO event_instance (eventId, date, time, length)
SELECT id, DATE_ADD(CURDATE(), INTERVAL 6 DAY), '13:00:00', 120 FROM event e WHERE title = 'Maker Saturday: 3D Printing'
    AND NOT EXISTS (SELECT 1 FROM event_instance WHERE eventId = e.id AND date = DATE_ADD(CURDATE(), INTERVAL 6 DAY))
UNION ALL
SELECT id, DATE_ADD(CURDATE(), INTERVAL 13 DAY), '13:00:00', 120 FROM event e WHERE title = 'Maker Saturday: 3D Printing'
    AND NOT EXISTS (SELECT 1 FROM event_instance WHERE eventId = e.id AND date = DATE_ADD(CURDATE(), INTERVAL 13 DAY));

-- Intro to Genealogy Research: 3 weekly instances (20 seats, waitlist cap 10)
INSERT INTO event_instance (eventId, date, time, length)
SELECT id, DATE_ADD(CURDATE(), INTERVAL 8 DAY), '10:00:00', 90 FROM event e WHERE title = 'Intro to Genealogy Research'
    AND NOT EXISTS (SELECT 1 FROM event_instance WHERE eventId = e.id AND date = DATE_ADD(CURDATE(), INTERVAL 8 DAY))
UNION ALL
SELECT id, DATE_ADD(CURDATE(), INTERVAL 15 DAY), '10:00:00', 90 FROM event e WHERE title = 'Intro to Genealogy Research'
    AND NOT EXISTS (SELECT 1 FROM event_instance WHERE eventId = e.id AND date = DATE_ADD(CURDATE(), INTERVAL 15 DAY))
UNION ALL
SELECT id, DATE_ADD(CURDATE(), INTERVAL 22 DAY), '10:00:00', 90 FROM event e WHERE title = 'Intro to Genealogy Research'
    AND NOT EXISTS (SELECT 1 FROM event_instance WHERE eventId = e.id AND date = DATE_ADD(CURDATE(), INTERVAL 22 DAY));

-- Digital Photography Workshop: 2 sessions (20 seats, unlimited waitlist)
-- Second session overrides seat count to 15 at the instance level
INSERT INTO event_instance (eventId, date, time, length)
SELECT id, DATE_ADD(CURDATE(), INTERVAL 10 DAY), '09:00:00', 120 FROM event e WHERE title = 'Digital Photography Workshop'
    AND NOT EXISTS (SELECT 1 FROM event_instance WHERE eventId = e.id AND date = DATE_ADD(CURDATE(), INTERVAL 10 DAY))
UNION ALL
SELECT id, DATE_ADD(CURDATE(), INTERVAL 17 DAY), '09:00:00', 120 FROM event e WHERE title = 'Digital Photography Workshop'
    AND NOT EXISTS (SELECT 1 FROM event_instance WHERE eventId = e.id AND date = DATE_ADD(CURDATE(), INTERVAL 17 DAY));

-- Instance-level numberOfSeats override: second Photography session capped at 15
SET @photoDate2 = DATE_FORMAT(DATE_ADD(CURDATE(), INTERVAL 17 DAY), '%Y-%m-%d');
SET @setInstanceSeats = IF(@hasInstanceSeats > 0,
    CONCAT(
        'UPDATE event_instance ei JOIN event e ON ei.eventId = e.id ',
        'SET ei.numberOfSeats = 15 ',
        'WHERE e.title = ''Digital Photography Workshop'' AND ei.date = ''', @photoDate2, ''''
    ),
    'SELECT ''numberOfSeats (event_instance) column not present, skipping'' AS info'
);
PREPARE stmt FROM @setInstanceSeats; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Instance-level waitingList override: disable waitlist on the second Photography session
SET @setInstanceWaitingList = IF(@hasInstanceWaitingList > 0,
    CONCAT(
        'UPDATE event_instance ei JOIN event e ON ei.eventId = e.id ',
        'SET ei.waitingList = 0 ',
        'WHERE e.title = ''Digital Photography Workshop'' AND ei.date = ''', @photoDate2, ''''
    ),
    'SELECT ''waitingList (event_instance) column not present, skipping'' AS info'
);
PREPARE stmt FROM @setInstanceWaitingList; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ============================================================
-- 9. Set Field Values on Events
-- ============================================================

-- Toddler Storytime
INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Reading' FROM event e, event_field f WHERE e.title = 'Toddler Storytime (Weekly)' AND f.name = 'Primary Topic'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Toddlers' FROM event e, event_field f WHERE e.title = 'Toddler Storytime (Weekly)' AND f.name = 'Target Age'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Storytime' FROM event e, event_field f WHERE e.title = 'Toddler Storytime (Weekly)' AND f.name = 'Program Type'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

-- Drop-in Device Help
INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Technology' FROM event e, event_field f WHERE e.title = 'Drop-in Device Help' AND f.name = 'Primary Topic'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Seniors' FROM event e, event_field f WHERE e.title = 'Drop-in Device Help' AND f.name = 'Target Age'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Drop-in' FROM event e, event_field f WHERE e.title = 'Drop-in Device Help' AND f.name = 'Program Type'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

-- History of Local Libraries (Lecture Info field set — includes speaker name)
INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Science' FROM event e, event_field f WHERE e.title = 'History of Local Libraries' AND f.name = 'Primary Topic'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Adults' FROM event e, event_field f WHERE e.title = 'History of Local Libraries' AND f.name = 'Target Age'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Lecture' FROM event e, event_field f WHERE e.title = 'History of Local Libraries' AND f.name = 'Program Type'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Dr. Jamie Wilson' FROM event e, event_field f WHERE e.title = 'History of Local Libraries' AND f.name = 'Speaker Name'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

-- Adult Book Club
INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Reading' FROM event e, event_field f WHERE e.title = 'Adult Book Club' AND f.name = 'Primary Topic'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Adults' FROM event e, event_field f WHERE e.title = 'Adult Book Club' AND f.name = 'Target Age'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Club' FROM event e, event_field f WHERE e.title = 'Adult Book Club' AND f.name = 'Program Type'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

-- Maker Saturday: 3D Printing (Workshop field set — equipment checkbox)
INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Technology' FROM event e, event_field f WHERE e.title = 'Maker Saturday: 3D Printing' AND f.name = 'Primary Topic'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Teens' FROM event e, event_field f WHERE e.title = 'Maker Saturday: 3D Printing' AND f.name = 'Target Age'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Workshop' FROM event e, event_field f WHERE e.title = 'Maker Saturday: 3D Printing' AND f.name = 'Program Type'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, '1' FROM event e, event_field f WHERE e.title = 'Maker Saturday: 3D Printing' AND f.name = 'Equipment Provided'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

-- Intro to Genealogy Research (Registration Form — email + special instructions textarea)
INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Science' FROM event e, event_field f WHERE e.title = 'Intro to Genealogy Research' AND f.name = 'Primary Topic'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Adults' FROM event e, event_field f WHERE e.title = 'Intro to Genealogy Research' AND f.name = 'Target Age'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Workshop' FROM event e, event_field f WHERE e.title = 'Intro to Genealogy Research' AND f.name = 'Program Type'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'events@library.org' FROM event e, event_field f WHERE e.title = 'Intro to Genealogy Research' AND f.name = 'Registration Email'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Please bring a laptop if you have one.' FROM event e, event_field f WHERE e.title = 'Intro to Genealogy Research' AND f.name = 'Special Instructions'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

-- Digital Photography Workshop (Workshop Details — equipment/accessible checkboxes, resource link URL)
INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Technology' FROM event e, event_field f WHERE e.title = 'Digital Photography Workshop' AND f.name = 'Primary Topic'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Teens' FROM event e, event_field f WHERE e.title = 'Digital Photography Workshop' AND f.name = 'Target Age'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'Workshop' FROM event e, event_field f WHERE e.title = 'Digital Photography Workshop' AND f.name = 'Program Type'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, '1' FROM event e, event_field f WHERE e.title = 'Digital Photography Workshop' AND f.name = 'Equipment Provided'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, '1' FROM event e, event_field f WHERE e.title = 'Digital Photography Workshop' AND f.name = 'Accessible'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'https://library.example.org/photography-resources' FROM event e, event_field f WHERE e.title = 'Digital Photography Workshop' AND f.name = 'Resource Link'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

INSERT INTO event_event_field (eventId, eventFieldId, value)
SELECT e.id, f.id, 'events@library.org' FROM event e, event_field f WHERE e.title = 'Digital Photography Workshop' AND f.name = 'Registration Email'
AND NOT EXISTS (SELECT 1 FROM event_event_field WHERE eventId = e.id AND eventFieldId = f.id);

COMMIT;
