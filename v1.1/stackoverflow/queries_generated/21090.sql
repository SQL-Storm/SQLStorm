-- {"query": "21090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1787} 

WITH ActiveUsers AS (
  SELECT 
    u.Id AS UserId,
    u.Reputation,
    u.CreationDate,
    u.UpVotes,
    u.DownVotes,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    AVG(p.Score) AS AvgPostScore
  FROM Users u
  INNER JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE u.Reputation > 100 
    AND u.LastAccessDate >= NOW() - INTERVAL '30 days'
    AND p.CreationDate >= NOW() - INTERVAL '1 year'
    AND p.Score IS NOT NULL
  GROUP BY u.Id, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes
  HAVING COUNT(DISTINCT p.Id) >= 5
),
HighActivityPosts AS (
  SELECT 
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.Title,
    p.Tags,
    p.CreationDate,
    COALESCE(p.ClosedDate, '9999-12-31'::timestamp) AS ClosedDate,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC, p.Score DESC) AS ViewRank,
    LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
    LEAD(p.Title) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextTitle,
    CASE 
      WHEN p.Tags LIKE '%javascript%' THEN 'JS'
      WHEN p.Tags LIKE '%python%' THEN 'Python'
      WHEN p.Tags IS NULL OR p.Tags = '' THEN 'NoTags'
      ELSE SUBSTRING(p.Tags, 2, POSITION('><' IN p.Tags) - 2)
    END AS PrimaryTag
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
    AND p.DeletionDate IS NULL
    AND (p.ClosedDate IS NULL OR p.ClosedDate > NOW() - INTERVAL '90 days')
),
UserPostStats AS (
  SELECT 
    au.UserId,
    au.PostCount,
    au.QuestionCount,
    au.AnswerCount,
    hap.PostId,
    hap.Score AS PostScore,
    hap.ViewCount,
    hap.ViewRank,
    hap.PrimaryTag,
    hap.CreationDate AS PostCreationDate,
    (au.UpVotes + au.DownVotes) AS TotalVotes,
    CASE 
      WHEN au.Reputation > 10000 THEN 'Elite'
      WHEN au.Reputation > 1000 THEN 'Veteran'
      ELSE 'Regular'
    END AS UserTier,
    -- Complex string manipulation for tag analysis
    LENGTH(COALESCE(hap.Tags, '')) - LENGTH(REPLACE(COALESCE(hap.Tags, ''), '><', '')) AS TagComplexity,
    -- NULL-safe calculations
    GREATEST(0, COALESCE(hap.PostScore, 0)) * COALESCE(au.Reputation, 1) AS ScoreWeightedByRep
  FROM ActiveUsers au
  INNER JOIN HighActivityPosts hap ON hap.OwnerUserId = au.UserId
  WHERE hap.ViewRank <= 10 OR hap.PostScore > 50
),
BadgeAchievements AS (
  SELECT 
    b.UserId,
    b.Name AS BadgeName,
    b.Date AS BadgeDate,
    b.Class,
    COUNT(*) OVER (PARTITION BY b.UserId) AS TotalBadges,
    ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS RecentBadgeRank,
    STRING_AGG(DISTINCT b.Name, ' | ') OVER (PARTITION BY b.UserId) AS AllBadges
  FROM Badges b
  INNER JOIN ActiveUsers au ON au.UserId = b.UserId
  WHERE b.Date >= NOW() - INTERVAL '2 years'
    AND b.Class IN (1, 2)  -- Gold and Silver only
)
SELECT 
  ups.UserId,
  u.DisplayName,
  u.Location,
  au.Reputation,
  au.AvgPostScore,
  ups.PostCount,
  ups.QuestionCount,
  ups.AnswerCount,
  ups.PostScore,
  ups.ViewCount,
  ups.PrimaryTag,
  ups.UserTier,
  ups.TagComplexity,
  ups.ScoreWeightedByRep,
  ba.BadgeName,
  ba.BadgeDate,
  ba.TotalBadges,
  ba.RecentBadgeRank,
  -- Complex predicate with subquery
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM Votes v 
      WHERE v.PostId = ups.PostId 
        AND v.UserId = ups.UserId 
        AND v.VoteTypeId IN (2, 3)  -- Upvote/Downvote
        AND v.CreationDate >= ups.PostCreationDate - INTERVAL '1 day'
    ) THEN 'SelfVoted'
    ELSE 'NoSelfVote'
  END AS SelfVoteStatus,
  -- Correlated subquery for average comparison
  (SELECT AVG(v.BountyAmount) 
   FROM Votes v 
   WHERE v.UserId = ups.UserId 
     AND v.VoteTypeId = 8  -- BountyStart
     AND v.BountyAmount IS NOT NULL
  ) AS AvgBountyOffered,
  -- Window function for ranking within user tiers
  RANK() OVER (PARTITION BY ups.UserTier ORDER BY ups.ViewCount DESC, ups.PostScore DESC) AS TierRank,
  -- Set operator simulation with conditional aggregation
  COUNT(DISTINCT CASE WHEN ba.Class = 1 THEN ba.BadgeName END) AS GoldBadges,
  COUNT(DISTINCT CASE WHEN ba.Class = 2 THEN ba.BadgeName END) AS SilverBadges,
  -- String expression for formatted output
  CONCAT(
    u.DisplayName, ' (', 
    COALESCE(u.Location, 'Unknown'), 
    ') - ', 
    ups.PrimaryTag, 
    ' posts: Q:', ups.QuestionCount, 
    ' A:', ups.AnswerCount
  ) AS UserProfileSummary,
  -- NULL logic with COALESCE chains
  COALESCE(
    ba.AllBadges, 
    (SELECT STRING_AGG(DISTINCT b2.Name, ' | ') 
     FROM Badges b2 
     WHERE b2.UserId = ups.UserId 
       AND b2.Date >= NOW() - INTERVAL '1 year'), 
    'No Recent Badges'
  ) AS RecentBadgesList
FROM UserPostStats ups
INNER JOIN ActiveUsers au ON au.UserId = ups.UserId
INNER JOIN Users u ON u.Id = ups.UserId
LEFT OUTER JOIN BadgeAchievements ba ON ba.UserId = ups.UserId 
  AND ba.RecentBadgeRank <= 3  -- Only top 3 recent badges
LEFT OUTER JOIN Comments c ON c.PostId = ups.PostId 
  AND c.Score > 5  -- High value comments
WHERE (ups.ViewRank <= 5 OR ups.PostScore > 100)
  AND (ba.BadgeDate IS NULL OR ba.BadgeDate >= NOW() - INTERVAL '6 months')
  AND NOT EXISTS (
    SELECT 1 FROM PostHistory ph 
    WHERE ph.PostId = ups.PostId 
      AND ph.PostHistoryTypeId = 12  -- Post Deleted
      AND ph.CreationDate > ups.PostCreationDate
  )
  AND (
    ups.PrimaryTag != 'NoTags' 
    OR (ups.PrimaryTag IS NULL AND ups.TagComplexity = 0)
  )
GROUP BY 
  ups.UserId, u.DisplayName, u.Location, au.Reputation, au.AvgPostScore,
  ups.PostCount, ups.QuestionCount, ups.AnswerCount, ups.PostScore, 
  ups.ViewCount, ups.PrimaryTag, ups.UserTier, ups.TagComplexity,
  ups.ScoreWeightedByRep, ba.BadgeName, ba.BadgeDate, ba.TotalBadges,
  ba.RecentBadgeRank, ups.PostCreationDate
HAVING COUNT(DISTINCT c.Id) > 0 OR ba.TotalBadges >= 2
ORDER BY 
  ups.UserTier DESC, 
  ups.ViewCount DESC NULLS LAST,
  au.Reputation DESC,
  ba.BadgeDate DESC NULLS FIRST
LIMIT 100;
