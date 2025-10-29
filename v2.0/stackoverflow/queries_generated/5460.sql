-- {"query": "5460.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 939} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
tag_summary AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
    p.Id AS PostId,
    p.OwnerUserId,
    p.Score,
    p.ViewCount
  FROM Posts p
  WHERE p.PostTypeId = 1
),
top_tags AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(t.Score) AS AvgScore,
    MAX(t.ViewCount) AS MaxViews
  FROM tag_summary t
  GROUP BY t.TagName
  ORDER BY PostCount DESC, AvgScore DESC
  LIMIT 20
),
author_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COALESCE(b.TotalBadges, 0) AS BadgeCount,
    COUNT(DISTINCT r.PostId) AS RecentlyCommentedPosts
  FROM Users u
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate >= NOW() - INTERVAL '7 days'
  LEFT JOIN (
    SELECT DISTINCT PostId
    FROM Comments
    WHERE CreationDate >= NOW() - INTERVAL '7 days'
  ) r ON r.PostId = c.PostId
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes, b.TotalBadges
),
complex_metrics AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.CreationDate,
    rq.LastActivityDate,
    rq.OwnerUserId,
    rq.Score,
    rq.ViewCount,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = rq.PostId AND v.VoteTypeId = 8) AS AvgBountyOnOpen,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rq.PostId AND v.VoteTypeId = 2) AS Upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rq.PostId AND v.VoteTypeId = 3) AS Downvotes,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rq.PostId) AS LinkCount
  FROM recent_questions rq
),
final_rows AS (
  SELECT
    f.PostId,
    f.Title,
    f.CreationDate,
    f.LastActivityDate,
    f.OwnerUserId,
    f.Score,
    f.ViewCount,
    f.Upvotes,
    f.Downvotes,
    f.LinkCount,
    COALESCE(a.DisplayName, 'Community') AS AuthorName,
    a.Reputation AS AuthorReputation,
    t.TagName,
    ts.PostCount AS PostsForTag
  FROM complex_metrics f
  LEFT JOIN Votes v ON v.PostId = f.PostId AND v.VoteTypeId = 6
  LEFT JOIN Users a ON a.Id = f.OwnerUserId
  LEFT JOIN LATERAL (
    SELECT tg.TagName, tg.PostCount
    FROM top_tags tg
    ORDER BY tg.PostCount DESC
    LIMIT 1
  ) t ON true
  LEFT JOIN (
    SELECT TagName, PostCount
    FROM top_tags
  ) ts ON ts.TagName = t.TagName
)
SELECT
  PostId,
  Title,
  AuthorName,
  AuthorReputation,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  Upvotes,
  Downvotes,
  LinkCount,
  TagName,
  PostsForTag
FROM final_rows
ORDER BY CreationDate DESC, Score DESC, ViewCount DESC
LIMIT 100;