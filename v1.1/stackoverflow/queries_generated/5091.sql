-- {"query": "5091.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1032} 
WITH
TopActiveUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT c.Id) AS TotalComments,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  WHERE u.Reputation > 1000 AND u.CreationDate < NOW() - INTERVAL '1 year'
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
BadgeStats AS (
  SELECT
    b.UserId,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges b
  WHERE b.Date > NOW() - INTERVAL '2 year'
  GROUP BY b.UserId
),
TopTags AS (
  SELECT
    t.TagName,
    SUM(t.Count) AS TotalTagCount,
    ROW_NUMBER() OVER (ORDER BY SUM(t.Count) DESC) AS TagRank
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
  GROUP BY t.TagName
  HAVING SUM(t.Count) > 500
)
SELECT
  u.UserId,
  u.DisplayName,
  u.Reputation,
  u.ReputationRank,
  u.TotalPosts,
  u.TotalComments,
  COALESCE(b.GoldBadges, 0) AS GoldBadges,
  COALESCE(b.SilverBadges, 0) AS SilverBadges,
  COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
  (
    SELECT COUNT(1)
    FROM Votes v
    WHERE v.UserId = u.UserId
      AND v.VoteTypeId = 2
      AND v.CreationDate > NOW() - INTERVAL '1 year'
  ) AS UpVotesLastYear,
  (
    SELECT COUNT(1)
    FROM Votes v
    WHERE v.UserId = u.UserId
      AND v.VoteTypeId = 3
      AND v.CreationDate > NOW() - INTERVAL '1 year'
  ) AS DownVotesLastYear,
  (
    SELECT COUNT(1)
    FROM Posts p2
    WHERE p2.OwnerUserId = u.UserId
      AND p2.PostTypeId = 1
      AND p2.ClosedDate IS NOT NULL
  ) AS ClosedQuestions,
  (
    SELECT STRING_AGG(tt.TagName, ', ' ORDER BY tt.TagRank)
    FROM TopTags tt
    WHERE EXISTS (
      SELECT 1
      FROM Posts p3
      WHERE p3.OwnerUserId = u.UserId
        AND POSITION('<' || tt.TagName || '>' IN p3.Tags) > 0
    )
  ) AS FrequentTags,
  (
    SELECT MAX(ph.CreationDate)
    FROM PostHistory ph
    WHERE ph.UserId = u.UserId
      AND ph.PostHistoryTypeId IN (
        SELECT Id FROM PostHistoryTypes WHERE Name ILIKE '%edit%'
      )
  ) AS LastEditActivity,
  (
    SELECT COUNT(1)
    FROM PostLinks pl
    WHERE pl.PostId IN (SELECT p4.Id FROM Posts p4 WHERE p4.OwnerUserId = u.UserId)
      AND pl.LinkTypeId = 3
  ) AS DuplicateLinksOriginated,
  (
    SELECT COUNT(DISTINCT pl2.PostId)
    FROM PostLinks pl2
    WHERE pl2.RelatedPostId IN (SELECT p5.Id FROM Posts p5 WHERE p5.OwnerUserId = u.UserId)
      AND pl2.LinkTypeId = 3
  ) AS DuplicateLinksReceived,
  CASE
    WHEN u.TotalPosts IS NULL OR u.TotalPosts = 0 THEN NULL
    ELSE ROUND(u.TotalComments*1.0 / u.TotalPosts, 2)
  END AS CommentsPerPost,
  (u.Reputation - 1000) / GREATEST(EXTRACT(year FROM age(NOW(), u.CreationDate)), 1) AS AvgReputationGrowthPerYear,
  COALESCE((
    SELECT MIN(p6.CreationDate)
    FROM Posts p6
    WHERE p6.OwnerUserId = u.UserId AND p6.PostTypeId = 2
  ), u.CreationDate) AS FirstAnswerDate
FROM TopActiveUsers u
LEFT JOIN BadgeStats b ON u.UserId = b.UserId
ORDER BY u.ReputationRank
LIMIT 50;