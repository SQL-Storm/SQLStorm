-- {"query": "5017.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 861} 
WITH
-- 1) Identify top users by reputation influence and recent activity
TopUsers AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
  WHERE u.AccountId IS NOT NULL
),
-- 2) Compute post activity metrics per user with CTEs and window functions
UserActivity AS (
  SELECT
    p.OwnerUserId AS UserId,
    COUNT(*) AS PostCount,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActive
  FROM Posts p
  GROUP BY p.OwnerUserId
),
-- 3) Recent tag activity for users (correlated subquery with array of tags)
RecentTagActivity AS (
  SELECT
    u.Id AS UserId,
    (SELECT STRING_AGG(t.TagName, ',') FROM unnest(string_to_array(p.Tags, '><')) AS TagName
     FROM Posts p
     WHERE p.OwnerUserId = u.Id
       AND p.Tags IS NOT NULL
     LIMIT 5) AS RecentTags
  FROM Users u
),
-- 4) Complex filtering: posts with complex predicates and null handling
ComplexPosts AS (
  SELECT
    pr.Id AS PostId,
    pr.OwnerUserId,
    pr.PostTypeId,
    pr.Score,
    pr.ViewCount,
    pr.Title,
    pr.Tags,
    pr.LastActivityDate,
    CASE
      WHEN pr.ClosedDate IS NULL THEN 'Open'
      ELSE 'Closed'
    END AS Status
  FROM Posts pr
  LEFT JOIN PostHistory ph ON ph.PostId = pr.Id
  WHERE (pr.Score > 5 OR pr.ViewCount > 100)
    AND (pr.LastActivityDate IS NOT NULL)
    AND (pr.OwnerUserId IS NULL OR pr.OwnerUserId > 0)
)
-- 5) Join with votes to add moderation signal and Bounty cues
SELECT
  tu.Id AS UserId,
  tu.DisplayName,
  tu.Reputation,
  ta.PostCount,
  ta.Questions,
  ta.Answers,
  ta.TotalViews,
  ra.RecentTags,
  COALESCE(cv.UpvotesFromRecent, 0) AS UpvotesFromRecent,
  COALESCE(bn.BountyTotal, 0) AS BountyTotal,
  STRING_AGG(CONCAT(c.Status, ': ', c.PostId), ';') AS PostStatuses
FROM TopUsers tu
JOIN UserActivity ta ON ta.UserId = tu.Id
LEFT JOIN RecentTagActivity ra ON ra.UserId = tu.Id
LEFT JOIN (
  SELECT
    v.UserId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesFromRecent
  FROM Votes v
  WHERE v.CreationDate >= NOW() - INTERVAL '30 days'
  GROUP BY v.UserId
) cv ON cv.UserId = tu.Id
LEFT JOIN (
  SELECT
    p.OwnerUserId,
    SUM(COALESCE(v.BountyAmount, 0)) AS BountyTotal
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 8
  GROUP BY p.OwnerUserId
) bn ON bn.OwnerUserId = tu.Id
LEFT JOIN (
  SELECT
    p.OwnerUserId AS UserId,
    STRING_AGG(CONCAT('Post', p.Id, ' (', p.Status, ')'), ', ') AS Statuses
  FROM ComplexPosts p
  GROUP BY p.OwnerUserId
) c ON c.UserId = tu.Id
WHERE tu rn <= 100
ORDER BY ta.PostCount DESC, ta.TotalViews DESC
LIMIT 100;