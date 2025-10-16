WITH
UserPostActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    DATE_TRUNC('week', p.CreationDate) AS WeekStart,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
    COUNT(*) AS TotalPosts,
    MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE u.Id IS NOT NULL
  GROUP BY u.Id, u.DisplayName, DATE_TRUNC('week', p.CreationDate)
),
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
    (SELECT MAX(ph.RevisionGUID) FROM PostHistory ph WHERE ph.PostId = p.Id) AS LastRevisionGUID
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
    AND p.Score >= (
      SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = p.OwnerUserId AND p2.PostTypeId IN (1,2)
    )
),
TagCooccurrence AS (
  SELECT
    t.TagName,
    t.Count,
    (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS TagPostCount
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
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
LEFT JOIN LATERAL (
  SELECT tc2.TagName, tc2.TagPostCount
  FROM (
    SELECT TRIM(BOTH ' ' FROM tag) AS tag
    FROM (
      SELECT
        REGEXP_SPLIT_TO_TABLE(
          TRIM(BOTH '()' FROM p.Tags),
          ','
        ) AS tag
      FROM Posts p
      WHERE p.Id = tp.PostId
    ) s
  ) tags
  JOIN TagCooccurrence tc2 ON tc2.TagName = tags.tag
  LIMIT 1
) tc ON TRUE
ORDER BY w.WeekStart DESC, w.RankInWeek, tp.Score DESC;