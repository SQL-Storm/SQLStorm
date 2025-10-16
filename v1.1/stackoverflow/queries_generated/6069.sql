-- {"query": "6069.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 815} 
WITH
-- 1) Weekly activity heatmap by user, including last editor and posts they own
UserPostActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    DATE_TRUNC('week', p.CreationDate) AS WeekStart,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
    COUNT(*) AS TotalPosts,
    MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE u.Id IS NOT NULL
  GROUP BY u.Id, u.DisplayName, DATE_TRUNC('week', p.CreationDate)
),
-- 2) Top posts per user by score with correlated subquery to fetch recent edits
TopPosts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastEditDate,
    p.LastActivityDate,
    (SELECT MAX(RevisionGUID) FROM PostHistory ph WHERE ph.PostId = p.Id) AS LastRevisionGUID
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
    AND p.Score >= (
      SELECT AVG(Score) FROM Posts WHERE OwnerUserId = p.OwnerUserId AND PostTypeId IN (1,2)
    )
  ORDER BY p.OwnerUserId, p.Score DESC
  LIMIT 100
),
-- 3) Tag correlations: for each tag, count how many posts link to other posts of same tag via Tags field
TagCooccurrence AS (
  SELECT
    t.TagName,
    t.Count,
    (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS TagPostCount
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
-- 4) Windowed ranking of posts by activity per user
RankedByActivity AS (
  SELECT
    pu.UserId,
    pu.UserName,
    pu.WeekStart,
    pu.TotalPosts,
    ROW_NUMBER() OVER (
      PARTITION BY pu.UserId
      ORDER BY pu.TotalPosts DESC, pu.LastActive DESC
    ) AS RankInWeek
  FROM (
    SELECT
      u.Id AS UserId,
      u.DisplayName AS UserName,
      DATE_TRUNC('week', p.CreationDate) AS WeekStart,
      COUNT(*) AS TotalPosts,
      MAX(p.LastActivityDate) AS LastActive
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, DATE_TRUNC('week', p.CreationDate)
  ) pu
)
SELECT
  -- 5) Compose final benchmark dataset
  u.Id AS UserId,
  u.DisplayName AS UserName,
  w.WeekStart,
  w.TotalPosts AS PostsThisWeek,
  w.RankInWeek,
  tp.PostId,
  tp.Title AS PostTitle,
  tp.Score,
  tp.ViewCount,
  tp.LastEditDate,
  tc.TagName,
  tc.TagPostCount,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate AS UserLastAccess
FROM RankedByActivity w
JOIN Users u ON u.Id = w.UserId
LEFT JOIN TopPosts tp ON tp.OwnerUserId = u.Id
LEFT JOIN TagCooccurrence tc ON tc.TagName IN (
  SELECT unnest(string_to_array(trim(both '()' FROM p.Tags), ','))
  FROM Posts p WHERE p.Id = tp.PostId
)
ORDER BY w.WeekStart DESC, w.RankInWeek, tp.Score DESC
;