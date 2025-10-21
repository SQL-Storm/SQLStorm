-- {"query": "377.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 26309} 
WITH
base_users AS (
  SELECT Id AS UserId,
         DisplayName,
         Reputation,
         CreationDate,
         LastAccessDate
  FROM Users
),
user_posts AS (
  SELECT OwnerUserId AS UserId,
         count(*) FILTER (WHERE PostTypeId = 1) AS QuestionCount,
         count(*) FILTER (WHERE PostTypeId = 2) AS AnswerCount,
         SUM(Score) AS TotalScore,
         MAX(LastActivityDate) AS LastActivityDate
  FROM Posts
  WHERE OwnerUserId IS NOT NULL
  GROUP BY OwnerUserId
),
user_badges AS (
  SELECT UserId, COUNT(*) AS BadgeCount
  FROM Badges
  GROUP BY UserId
),
user_votes AS (
  SELECT UserId, COUNT(*) AS VoteCount
  FROM Votes
  GROUP BY UserId
),
per_user_tags AS (
  SELECT p.OwnerUserId AS UserId,
         t.TagName AS TagName,
         COUNT(*) AS TagPostCount
  FROM Posts p
  CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName)
  GROUP BY p.OwnerUserId, t.TagName
),
top_user_tag AS (
  SELECT UserId, TopTagName, TagPostCount
  FROM (
    SELECT UserId, TagName AS TopTagName, TagPostCount,
           ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagPostCount DESC, TagName) AS rn
    FROM per_user_tags
  ) s
  WHERE rn = 1
),
last_editor AS (
  SELECT u.Id AS UserId,
         (
           SELECT ul.DisplayName
           FROM Posts p
           JOIN Users ul ON ul.Id = p.LastEditorUserId
           WHERE p.OwnerUserId = u.Id
           ORDER BY p.LastEditDate DESC
           LIMIT 1
         ) AS LastEditorName
  FROM Users u
),
user_combined AS (
  SELECT
    bu.UserId,
    bu.DisplayName,
    bu.Reputation,
    bu.CreationDate,
    bu.LastAccessDate,
    COALESCE(le.LastEditorName, 'System') AS LastEditorName,
    COALESCE(pp.TotalScore, 0) AS TotalScore,
    COALESCE(pp.QuestionCount, 0) AS QuestionCount,
    COALESCE(pp.AnswerCount, 0) AS AnswerCount,
    COALESCE(vv.VoteCount, 0) AS VoteCount,
    COALESCE(bb.BadgeCount, 0) AS BadgeCount,
    COALESCE(tu.TopTagName, 'NoTag') AS TopTagName,
    COALESCE(tu.TagPostCount, 0) AS TopTagCount,
    COALESCE(pp.LastActivityDate, bu.CreationDate) AS LastActivityDate
  FROM base_users bu
  LEFT JOIN last_editor le ON le.UserId = bu.UserId
  LEFT JOIN user_posts pp ON pp.UserId = bu.UserId
  LEFT JOIN user_votes vv ON vv.UserId = bu.UserId
  LEFT JOIN user_badges bb ON bb.UserId = bu.UserId
  LEFT JOIN top_user_tag tu ON tu.UserId = bu.UserId
)
SELECT *
FROM (
  SELECT
     uc.UserId,
     (uc.DisplayName || ' (' || uc.Reputation || ')') AS DisplayName,
     uc.Reputation,
     uc.CreationDate,
     uc.LastAccessDate,
     uc.LastEditorName,
     uc.TotalScore,
     uc.QuestionCount,
     uc.AnswerCount,
     uc.VoteCount,
     uc.BadgeCount,
     uc.TopTagName,
     uc.TopTagCount,
     uc.LastActivityDate
  FROM user_combined uc
  ORDER BY uc.Reputation DESC NULLS LAST
  LIMIT 100
) AS first_part
UNION ALL
SELECT
  -1 AS UserId,
  'BenchmarkTotal' AS DisplayName,
  SUM(uc.Reputation) AS Reputation,
  NULL AS CreationDate,
  NULL AS LastAccessDate,
  NULL AS LastEditorName,
  SUM(uc.TotalScore) AS TotalScore,
  SUM(uc.QuestionCount) AS QuestionCount,
  SUM(uc.AnswerCount) AS AnswerCount,
  SUM(uc.VoteCount) AS VoteCount,
  SUM(uc.BadgeCount) AS BadgeCount,
  NULL AS TopTagName,
  NULL AS TopTagCount,
  MAX(uc.LastActivityDate) AS LastActivityDate
FROM user_combined uc;