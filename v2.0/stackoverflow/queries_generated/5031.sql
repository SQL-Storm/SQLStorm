-- {"query": "5031.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1142} 
WITH recent_user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreated,
    u.LastAccessDate,
    COUNT(p.Id) AS PostCount,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.LastActivityDate) AS LastActivity,
    STRING_AGG(DISTINCT b.Name, ',') AS Badges Earned
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE u.AccountId IS NOT NULL
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
complex_post_metrics AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.PostTypeId,
    p.OwnerUserId,
    COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
    CASE
      WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id)
      ELSE 0
    END AS CommentCount,
    CASE
      WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2)
      ELSE 0
    END AS UpVotes,
    CASE
      WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3)
      ELSE 0
    END AS DownVotes,
    CASE
      WHEN p.PostTypeId IN (1,2) THEN (SELECT STRING_AGG(CONCAT(vt.Name, ':', v.BountyAmount), '|') 
                                      FROM Votes v 
                                      JOIN VoteTypes vt ON vt.Id = v.VoteTypeId 
                                      WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3,8,9))
      ELSE NULL
    END AS VoteSummary
  FROM Posts p
  LEFT JOIN LATERAL (
    SELECT 1
  ) AS d ON true
),
outer_join_example AS (
  SELECT
    rp.PostId AS RelatedPostId,
    rp.Title AS RelatedPostTitle,
    rp2.Id AS LinkedPostId,
    rp2.Title AS LinkedPostTitle
  FROM Posts rp
  LEFT JOIN PostLinks pl ON pl.RelatedPostId = rp.Id
  LEFT JOIN Posts rp2 ON rp2.Id = pl.PostId
  WHERE rp.PostTypeId = 1
),
tag_wiki_overlap AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    t.Count,
    p.Id AS PostId,
    p.Title AS PostTitle,
    p.CreationDate
  FROM Tags t
  JOIN Posts p ON p.Id = t.WikiPostId
  WHERE t.IsModeratorOnly = 0
),
date_windows AS (
  SELECT
    CURRENT_DATE AS CurrentDate,
    DATE_TRUNC('month', CURRENT_DATE) AS MonthStart,
    DATE_TRUNC('year', CURRENT_DATE) AS YearStart
),
combined AS (
  SELECT
    rua.UserId,
    rua.DisplayName,
    rua.Reputation,
    cpm.PostId,
    cpm.Title,
    cpm.Score,
    cpm.ViewCount,
    cpm.CommentCount,
    cpm.UpVotes,
    cpm.DownVotes,
    rw.LastActivity,
    rw.Badges
  FROM recent_user_activity rua
  JOIN complex_post_metrics cpm ON cpm.OwnerUserId = rua.UserId
  LEFT JOIN (
    SELECT
      p.Id,
      p.LastActivityDate AS LastActivity
    FROM Posts p
  ) rw ON rw.Id = cpm.PostId
  WHERE cpm.Score > 0
)
SELECT
  json_build_object(
    'benchmark', json_build_object(
      'description', 'Complex query covering CTEs, window-like aggregations, correlated subqueries, and multiple joins',
      'date', CURRENT_TIMESTAMP
    ),
    'users', json_agg(DISTINCT json_build_object(
      'userId', cr.UserId,
      'displayName', cr.DisplayName,
      'reputation', cr.Reputation,
      'userCreated', cr.UserCreated,
      'lastAccess', cr.LastAccessDate,
      'postCount', cr.PostCount,
      'avgPostScore', cr.AvgPostScore,
      'lastActivity', cr.LastActivity
    )),
    'posts', json_agg(DISTINCT json_build_object(
      'postId', cc.PostId,
      'title', cc.Title,
      'postType', cc.PostTypeId,
      'ownerUserId', cc.OwnerUserId,
      'acceptedAnswer', cc.AcceptedAnswerId,
      'commentCount', cc.CommentCount,
      'upVotes', cc.UpVotes,
      'downVotes', cc.DownVotes,
      'score', cc.Score,
      'views', cc.ViewCount,
      'creationDate', cc.CreationDate,
      'lastActivityDate', cc.LastActivityDate,
      'voteSummary', cc.VoteSummary
    ))
  ) AS BenchmarkResult
FROM combined cr
JOIN combined cc ON true
LIMIT 1;