WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    p.CommentCount
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days'
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn,
    t.IsModeratorOnly
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.AccountId,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount
  FROM Users u
),
Combined AS (
  SELECT
    rap.PostId,
    rap.Title,
    rap.CreationDate,
    rap.LastActivityDate,
    rap.OwnerUserId,
    rap.Score,
    rap.ViewCount,
    rap.Tags,
    rap.AnswerCount,
    rap.CommentCount,
    u.UserId AS AuthorId,
    u.DisplayName AS AuthorName,
    u.Reputation,
    u.Location,
    u.AccountId,
    u.CreationDate AS AuthorCreationDate,
    u.LastAccessDate AS AuthorLastAccess
  FROM RecentActivePosts rap
  LEFT JOIN UserStats u ON rap.OwnerUserId = u.UserId
),
Filtered AS (
  SELECT
    c.PostId,
    c.Title,
    c.CreationDate,
    c.LastActivityDate,
    c.OwnerUserId,
    c.Score,
    c.ViewCount,
    c.Tags,
    c.AnswerCount,
    c.CommentCount,
    c.AuthorId,
    c.AuthorName,
    c.Reputation,
    c.Location,
    c.AccountId,
    c.AuthorCreationDate,
    c.AuthorLastAccess,
    CASE
      WHEN c.Score > 0 THEN 'positive'
      WHEN c.Score < 0 THEN 'negative'
      ELSE 'neutral'
    END AS ScoreCategory,
    CASE
      WHEN c.ViewCount > 10000 THEN TRUE
      ELSE FALSE
    END AS Viral
  FROM Combined c
  JOIN TopTags tt ON POSITION(tt.TagName IN c.Tags) > 0
  WHERE c.AnswerCount IS NOT NULL
),
Aggregated AS (
  SELECT
    tt.rn AS TagRank,
    tt.TagName,
    COUNT(*) AS PostsWithTag,
    AVG(f.Score) AS AvgScore,
    SUM(CASE WHEN f.Viral THEN 1 ELSE 0 END) AS ViralPosts
  FROM Filtered f
  JOIN (
    SELECT TagName, ROW_NUMBER() OVER (ORDER BY Count DESC) AS rn
    FROM Tags
    WHERE IsModeratorOnly = FALSE
  ) AS tt
    ON POSITION(tt.TagName IN f.Tags) > 0
  GROUP BY tt.TagName, tt.rn
)
SELECT
  a.TagRank,
  a.TagName,
  a.PostsWithTag,
  a.AvgScore,
  a.ViralPosts,
  (
    SELECT STRING_AGG(DISTINCT (u.DisplayName || '(' || u.Reputation || ')'), ', ')
    FROM Users u
    WHERE u.Id IN (SELECT AuthorId FROM Filtered)
  ) AS SampleAuthors
FROM Aggregated a
ORDER BY a.TagRank ASC
LIMIT 50;