-- {"query": "5571.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 882} 
WITH recent_user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate DESC) AS rn
  FROM Users u
),
top_badges AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    STRING_AGG(b.Name, ', ') AS Badges
  FROM Badges b
  GROUP BY b.UserId
),
high_activity_posts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Title,
    p.Tags,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense
  FROM Posts p
  WHERE p.LastActivityDate >= NOW() - INTERVAL '90 days'
),
voter_summary AS (
  SELECT
    v.UserId,
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END) AS BountyStartsGiven
  FROM Votes v
  GROUP BY v.UserId, v.PostId
),
complex_calc AS (
  SELECT
    rua.UserId,
    rua.DisplayName,
    ra.BadgeCount,
    ha.PostId,
    ha.PostTypeId,
    ha.Title,
    ha.Tags,
    ha.ViewCount,
    ha.Score,
    ha.LastActivityDate,
    ha.CommentCount,
    ha.AnswerCount,
    ha.FavoriteCount,
    ha.ContentLicense,
    (ha.ViewCount * 0.75) + (ha.Score * 1.25) AS EngagementScore,
    (EXTRACT(epoch FROM ha.LastActivityDate - rua.UserCreationDate) / 3600) AS HoursSinceAccountCreated,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ha.PostId) AS TotalComments
  FROM recent_user_activity rua
  LEFT JOIN top_badges ra ON ra.UserId = rua.Id
  LEFT JOIN high_activity_posts ha ON ha.OwnerUserId = rua.Id
  LEFT JOIN voter_summary vs ON vs.UserId = rua.Id
  WHERE rua.rn = 1
)
SELECT
  cc.UserId,
  cc.DisplayName,
  cc.BadgeCount,
  cc.PostId,
  cc.PostTypeId,
  CASE
    WHEN cc.PostTypeId = 1 THEN 'Question'
    WHEN cc.PostTypeId = 2 THEN 'Answer'
    ELSE 'Other'
  END AS PostKind,
  cc.Title,
  cc.Tags,
  cc.ViewCount,
  cc.Score,
  cc.LastActivityDate,
  cc.CommentCount,
  cc.AnswerCount,
  cc.FavoriteCount,
  cc.ContentLicense,
  ROUND(cc.EngagementScore, 2) AS EngagementScore,
  ROUND(cc.HoursSinceAccountCreated, 2) AS HoursSinceAccountCreated,
  cc.TotalComments,
  COALESCE(vs.UpVotesGiven, 0) AS UpVotesGiven,
  COALESCE(vs.DownVotesGiven, 0) AS DownVotesGiven,
  COALESCE(vs.CloseVotesGiven, 0) AS CloseVotesGiven,
  COALESCE(vs.BountyStartsGiven, 0) AS BountyStartsGiven
FROM complex_calc cc
LEFT JOIN Votes v ON v.PostId = cc.PostId
LEFT JOIN voter_summary vs ON vs.UserId = cc.UserId
ORDER BY cc.EngagementScore DESC, cc.HoursSinceAccountCreated ASC
LIMIT 100;