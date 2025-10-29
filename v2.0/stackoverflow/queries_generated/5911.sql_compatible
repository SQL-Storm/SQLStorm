WITH recent_user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.LastAccessDate,
    u.AccountId,
    COUNT(p.Id) AS PostCount,
    SUM(p.Score) AS ScoreSum,
    ARRAY_AGG(DISTINCT t.Name) AS PostTypes
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN PostTypes t ON p.PostTypeId = t.Id
  WHERE u.Reputation > 100
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.LastAccessDate, u.AccountId
),
top_tags AS (
  SELECT
    t.TagName,
    t.Count,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
tag_activity AS (
  SELECT
    p.OwnerUserId AS UserId,
    t.TagName,
    COUNT(*) AS QuestionCount,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActive
  FROM Posts p
  JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
  WHERE p.PostTypeId = 1
  GROUP BY p.OwnerUserId, t.TagName
)
SELECT
  rau.UserId,
  rau.DisplayName,
  rau.Reputation,
  rau.LastAccessDate,
  rau.AccountId,
  rau.PostCount,
  rau.ScoreSum,
  rau.PostTypes,
  ta.TagName,
  ta.QuestionCount,
  ta.TotalViews,
  ta.LastActive
FROM recent_user_activity rau
LEFT JOIN tag_activity ta ON ta.UserId = rau.UserId
LEFT JOIN top_tags tt ON tt.rn = 1
WHERE rau.Reputation > 100
ORDER BY rau.Reputation DESC, rau.LastAccessDate DESC
LIMIT 1;