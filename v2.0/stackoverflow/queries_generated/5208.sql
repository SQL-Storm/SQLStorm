-- {"query": "5208.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 632} 
WITH user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.AboutMe,
    COALESCE(SUM(v.BountyAmount),0) AS TotalBounties,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(CASE WHEN p.PostTypeId = 1 AND v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesOnQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 AND v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesOnAnswers,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCast,
    MAX(p.CreationDate) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE u.AccountId IS NOT NULL
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.AboutMe
),
recent_activity AS (
  SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.CreationDate,
    ua.LastAccessDate,
    ua.Location,
    ua.TotalBounties,
    ua.PostCount,
    ua.LastPostDate,
    ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC, ua.TotalBounties DESC, ua.LastPostDate DESC) AS rn
  FROM user_activity ua
  LEFT JOIN Badges b ON b.UserId = ua.UserId
  GROUP BY ua.UserId, ua.DisplayName, ua.Reputation, ua.CreationDate, ua.LastAccessDate, ua.Location, ua.TotalBounties, ua.PostCount, ua.LastPostDate
)
SELECT
  ra.rn AS rank,
  ra.DisplayName,
  ra.Reputation,
  ra.Location,
  ra.TotalBounties,
  ra.PostCount,
  ra.LastPostDate,
  -- Complex derived metrics
  CAST( (ra.PostCount * 1.0) / NULLIF(DATE_PART('day', NOW() - ra.CreationDate), 0) AS numeric(12,4) ) AS posts_per_day,
  (SELECT AVG(Score) FROM Posts p2 WHERE p2.OwnerUserId = ra.UserId) AS avg_post_score,
  (SELECT COUNT(*) FROM Badges b2 WHERE b2.UserId = ra.UserId AND b2.Class = 1) AS gold_badges,
  (SELECT STRING_AGG(b2.Name, ',') FROM Badges b2 WHERE b2.UserId = ra.UserId AND b2.Class = 2) AS silver_badges
FROM recent_activity ra
WHERE ra.rn <= 100
ORDER BY ra.rn;