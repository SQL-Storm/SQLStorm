-- {"query": "5588.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 733}
WITH
TopUsers AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
  WHERE u.Reputation > 1000
),
UserActivity AS (
  SELECT
    p.OwnerUserId AS UserId,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
    SUM(p.ViewCount) AS TotalViews,
    SUM(p.Score) AS ScoreSum,
    MAX(p.LastActivityDate) AS LastActive
  FROM Posts p
  GROUP BY p.OwnerUserId
),
BadgeInfluence AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    SUM(CASE WHEN COALESCE(b.TagBased, FALSE) = TRUE THEN 1 ELSE 0 END) AS TagBadges
  FROM Badges b
  GROUP BY b.UserId
),
LatestEdits AS (
  SELECT
    ph.UserId,
    ph.PostId,
    ph.CreationDate,
    ph.PostHistoryTypeId,
    ph.Comment,
    ROW_NUMBER() OVER (PARTITION BY ph.UserId ORDER BY ph.CreationDate DESC) AS rn
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4,5,6,10,11)
)
SELECT
  tu.Id AS UserId,
  tu.DisplayName,
  tu.Reputation,
  tu.LastAccessDate,
  COALESCE(ua.QuestionCount, 0) AS QuestionCount,
  COALESCE(ua.AnswerCount, 0) AS AnswerCount,
  COALESCE(ua.TotalViews, 0) AS TotalViews,
  COALESCE(ua.ScoreSum, 0) AS ScoreSum,
  COALESCE(bu.BadgeCount, 0) AS BadgeCount,
  COALESCE(bu.TagBadges, 0) AS TagBadges,
  la.LastActive AS LastEditActiveDate,
  ARRAY_AGG(CASE WHEN le.PostHistoryTypeId IN (4,5) THEN le.PostId END) FILTER (WHERE le.rn = 1) AS RecentlyEditedPostIds,
  CONCAT_WS(' | ',
    COALESCE(tu.DisplayName, 'Unknown'),
    -- format timestamp in a portable ISO 8601 style using CAST to varchar
    CAST(tu.LastAccessDate AS VARCHAR),
    COALESCE(NULLIF(tu.Location, ''), 'NoLocation')
  ) AS Hints
FROM TopUsers tu
LEFT JOIN UserActivity ua ON ua.UserId = tu.Id
LEFT JOIN BadgeInfluence bu ON bu.UserId = tu.Id
LEFT JOIN LatestEdits le ON le.UserId = tu.Id AND le.rn = 1
LEFT JOIN (
  SELECT ph.UserId, MAX(ph.CreationDate) AS LastActive
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (10,11)
  GROUP BY ph.UserId
) la ON la.UserId = tu.Id
WHERE tu.rn <= 200
GROUP BY
  tu.Id,
  tu.DisplayName,
  tu.Reputation,
  tu.LastAccessDate,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.TotalViews,
  ua.ScoreSum,
  bu.BadgeCount,
  bu.TagBadges,
  la.LastActive,
  tu.Location,
  tu.CreationDate,
  tu.rn
ORDER BY tu.Reputation DESC, tu.LastAccessDate DESC;