-- {"query": "5580.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 724} 
WITH recent_posts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.CreationDate >= now() - interval '30 days'
),
tag_popular AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName,
    p.Id AS PostId,
    p.Score,
    p.ViewCount,
    p.LastActivityDate
  FROM recent_posts p
),
tag_rank AS (
  SELECT
    TagName,
    SUM(Score) AS ScoreSum,
    AVG(Score) AS AvgScore,
    SUM(ViewCount) AS TotalViews,
    MAX(LastActivityDate) AS LastActive
  FROM tag_popular
  GROUP BY TagName
),
top_tags AS (
  SELECT
    TagName
  FROM tag_rank
  WHERE ScoreSum > (SELECT AVG(ScoreSum) FROM tag_rank)
  ORDER BY ScoreSum DESC
  LIMIT 50
),
cross_joined AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    tb.Name AS BadgeName,
    tb.Date AS BadgeDate,
    COUNT(DISTINCT p.Id) AS PostsWithTopTag
  FROM Users u
  LEFT JOIN Badges tb ON tb.UserId = u.Id
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT DISTINCT p.Id
    FROM Posts p
    JOIN tag_popular t ON t.PostId = p.Id
    WHERE t.TagName IN (SELECT TagName FROM top_tags)
  ) tposts ON tposts.Id = p.Id
  WHERE u.Id IN (SELECT DISTINCT OwnerUserId FROM Posts)
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes, tb.Name, tb.Date
),
final AS (
  SELECT
    cu.UserId,
    cu.DisplayName,
    cu.Reputation,
    cu.UserCreationDate,
    cu.LastAccessDate,
    cu.Views,
    cu.UpVotes,
    cu.DownVotes,
    cu.BadgeName,
    cu.BadgeDate,
    cu.PostsWithTopTag,
    ROW_NUMBER() OVER (
      PARTITION BY cu.UserId
      ORDER BY cu.PostsWithTopTag DESC, cu.Reputation DESC, cu.LastAccessDate DESC
    ) AS rn
  FROM cross_joined cu
)
SELECT
  f.UserId,
  f.DisplayName,
  f.Reputation,
  f.UserCreationDate,
  f.LastAccessDate,
  f.Views,
  f.UpVotes,
  f.DownVotes,
  f.BadgeName,
  f.BadgeDate,
  f.PostsWithTopTag
FROM final f
WHERE f.rn = 1
ORDER BY f.Reputation DESC, f.PostsWithTopTag DESC
LIMIT 100;