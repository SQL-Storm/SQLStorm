-- {"query": "157.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2073} 
WITH
RecentEdits AS (
  SELECT
    ph.PostId,
    ph.CreationDate AS EditDate,
    ph.UserId AS EditorId,
    ph.Text,
    ph.RevisionGUID
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4,5,6,10,16,24,33,34) -- edits, close notices, migrations, etc.
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COALESCE(u.WebsiteUrl, '') AS WebsiteUrl,
    COALESCE(u.AboutMe, '') AS AboutMe,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
    MAX(p.LastActivityDate) AS LastActivity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    u.Location, u.Views, u.UpVotes, u.DownVotes, u.WebsiteUrl, u.AboutMe
),
EditsPerUser AS (
  SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.CreationDate,
    ua.LastAccessDate,
    ua.Location,
    ua.Views,
    ua.UpVotes,
    ua.DownVotes,
    ua.WebsiteUrl,
    ua.AboutMe,
    ROW_NUMBER() OVER (PARTITION BY ua.UserId ORDER BY re.EditDate DESC) AS rn,
    MAX(pa.EditDate) OVER (PARTITION BY ua.UserId) AS LastEditDate,
    re.EditDate AS MostRecentEdit
  FROM UserActivity ua
  LEFT JOIN RecentEdits re ON re.EditorId = ua.UserId
  LEFT JOIN Posts p ON p.Id = re.PostId
  LEFT JOIN (
    SELECT
      ph.PostId,
      ph.CreationDate AS EditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,10)
  ) pa ON pa.PostId = p.Id
),
TagUsage AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagMentionCount
  FROM Tags t
  WHERE t.IsModeratorOnly = false
  GROUP BY t.TagName
),
ActiveQuestionTags AS (
  SELECT
    t.TagName,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCountWithTag
  FROM Posts p
  JOIN UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(TagName) ON true
  GROUP BY t.TagName
),
Combined AS (
  SELECT
    epu.UserId,
    epu.DisplayName,
    epu.Reputation,
    epu.LastEditDate,
    epu.MostRecentEdit,
    epu.Location,
    epu.Views,
    epu.UpVotes,
    epu.DownVotes,
    epu.WebsiteUrl,
    epu.AboutMe,
    COALESCE(uc.QuestionCount, 0) AS QuestionCount,
    COALESCE(uc.AnswerCount, 0) AS AnswerCount,
    COALESCE(ta.TagUsage, 0) AS TopTagEngagement
  FROM EditsPerUser epu
  LEFT JOIN (
    SELECT
      p.OwnerUserId,
      COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
      COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount
    FROM Posts p
    GROUP BY p.OwnerUserId
  ) uc ON uc.OwnerUserId = epu.UserId
  LEFT JOIN (
    SELECT
      tu.TagName,
      SUM(uu.Cnt) AS TagUsage
    FROM ActiveQuestionTags au
    JOIN TagUsage tu ON tu.TagName = au.TagName
    GROUP BY tu.TagName
  ) ta ON ta.TagName = (SELECT TagName FROM Tags t WHERE t.IsModeratorOnly = false LIMIT 1)
)
SELECT
  c.UserId,
  c.DisplayName,
  c.Reputation,
  c.LastEditDate,
  COALESCE(c.MostRecentEdit, NULL) AS MostRecentEditDate,
  c.Location,
  c.Views,
  c.UpVotes,
  c.DownVotes,
  c.WebsiteUrl,
  c.AboutMe,
  c.QuestionCount,
  c.AnswerCount,
  c.TopTagEngagement,
  -- string expression and NULL-safe logic
  CASE
    WHEN c.Location IS NULL THEN '(unknown)'
    ELSE c.Location
  END AS LocationSafe,
  CONCAT_WS(' | ', c.DisplayName, COALESCE(NULLIF(c.Location, ''), '(no location)')) AS DisplayWithLocation
FROM Combined c
ORDER BY c.Reputation DESC NULLS LAST, c.LastEditDate DESC NULLS LAST
LIMIT 100;