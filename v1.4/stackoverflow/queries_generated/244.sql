-- {"query": "244.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 7226} 
WITH
recent_posts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Tags,
    p.Score,
    p.ViewCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount
  FROM Posts p
  WHERE p.LastActivityDate > now() - interval '1 year'
),
populated AS (
  SELECT
    rp.*,
    COALESCE(rp.Score,0) * 2.0 +
    COALESCE(rp.ViewCount,0) * 0.6 +
    COALESCE((rp.UpVotes - rp.DownVotes),0) * 0.8 +
    COALESCE(rp.CommentCount,0) * 0.2 AS popularity
  FROM recent_posts rp
),
ranked AS (
  SELECT
    PostId,
    OwnerUserId,
    Title,
    PostTypeId,
    CreationDate,
    LastActivityDate,
    Tags,
    Score,
    ViewCount,
    UpVotes,
    DownVotes,
    CommentCount,
    popularity,
    ROW_NUMBER() OVER (PARTITION BY OwnerUserId, PostTypeId ORDER BY popularity DESC, LastActivityDate DESC) AS rn
  FROM populated
),
top_questions AS (
  SELECT PostId, OwnerUserId, Title, CreationDate, LastActivityDate, Tags, Score, ViewCount, UpVotes, DownVotes, CommentCount
  FROM ranked
  WHERE PostTypeId = 1 AND rn <= 5
),
top_answers AS (
  SELECT PostId, OwnerUserId, Title, CreationDate, LastActivityDate, Tags, Score, ViewCount, UpVotes, DownVotes, CommentCount
  FROM ranked
  WHERE PostTypeId = 2 AND rn <= 5
),
all_top AS (
  SELECT 'question' AS Type, tq.PostId, tq.OwnerUserId, tq.Title, tq.CreationDate AS ActivityDate, tq.Score, tq.ViewCount, tq.UpVotes, tq.DownVotes, tq.CommentCount, tq.LastActivityDate
  FROM top_questions tq
  UNION ALL
  SELECT 'answer' AS Type, ta.PostId, ta.OwnerUserId, ta.Title, ta.CreationDate AS ActivityDate, ta.Score, ta.ViewCount, ta.UpVotes, ta.DownVotes, ta.CommentCount, ta.LastActivityDate
  FROM top_answers ta
),
user_summary AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COALESCE(u.Location, '') AS Location,
    u.Reputation,
    CONCAT_WS(' | ', COALESCE(u.DisplayName, ''), COALESCE(u.Location, ''), 'Rep:' || u.Reputation) AS ProfileSummary
  FROM Users u
),
badge_counts AS (
  SELECT UserId, COUNT(*) AS BadgeCount
  FROM Badges
  GROUP BY UserId
)
SELECT
  us.UserId,
  us.DisplayName,
  us.Location,
  us.Reputation,
  ac.Type,
  ac.Title,
  ac.ActivityDate,
  ac.Score,
  ac.ViewCount,
  (ac.UpVotes - ac.DownVotes) AS NetVotes,
  ac.CommentCount,
  COALESCE(bc.BadgeCount, 0) AS BadgeCount,
  us.ProfileSummary
FROM user_summary us
LEFT JOIN all_top ac ON ac.OwnerUserId = us.UserId
LEFT JOIN badge_counts bc ON bc.UserId = us.UserId
ORDER BY us.Reputation DESC NULLS LAST, us.UserId
LIMIT 200;