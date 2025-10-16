-- {"query": "28060.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1512} 

WITH UserBadgeSummary AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(Date) AS LastBadgeDate
    FROM Badges
    GROUP BY UserId
), PostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.LastActivityDate) AS LastPostActivity
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
), VoteAnalysis AS (
    SELECT
        v.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.PostId END) AS Bookmarks
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
), CommentStats AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
)
SELECT 
    u.Id AS UserId,
    CONCAT(u.DisplayName, ' (', COALESCE(u.Location, 'Unknown'), ')') AS UserLabel,
    u.Reputation,
    u.CreationDate AS JoinDate,
    DATEDIFF('year', u.CreationDate, CURRENT_TIMESTAMP) AS YearsActive,
    (ubs.GoldBadges * 10 + ubs.SilverBadges * 5 + ubs.BronzeBadges) AS BadgeScore,
    pa.TotalPosts,
    pa.Questions,
    pa.Answers,
    pa.AvgPostScore,
    va.Upvotes,
    va.Downvotes,
    va.Bookmarks,
    cs.TotalComments,
    cs.AvgCommentLength,
    RANK() OVER (ORDER BY u.Reputation DESC) AS GlobalRank,
    RANK() OVER (PARTITION BY CASE 
        WHEN u.Reputation >= 100000 THEN 'Legend'
        WHEN u.Reputation >= 10000 THEN 'Expert'
        WHEN u.Reputation >= 1000 THEN 'Contributor'
        ELSE 'Member' END 
        ORDER BY u.Reputation DESC) AS TierRank,
    (SELECT COUNT(*) 
     FROM Posts p2 
     WHERE p2.OwnerUserId = u.Id 
       AND p2.Id IN (SELECT RelatedPostId FROM PostLinks WHERE LinkTypeId = 3)) AS DuplicatePosts,
    (SELECT STRING_AGG(TagName, ', ' ORDER BY Count DESC) 
     FROM Tags t 
     WHERE t.Id IN (SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) 
                    FROM Posts p 
                    WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1)) AS TopTags
FROM Users u
LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
LEFT JOIN PostActivity pa ON u.Id = pa.OwnerUserId
LEFT JOIN VoteAnalysis va ON u.Id = va.UserId
LEFT JOIN CommentStats cs ON u.Id = cs.UserId
WHERE u.Reputation > 1000
  AND EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.Score > 50)
  AND (va.Upvotes > 100 OR va.Bookmarks > 20)
  AND COALESCE(ubs.LastBadgeDate, u.CreationDate) > DATEADD('year', -2, CURRENT_TIMESTAMP)
HAVING TotalPosts > 10 OR TotalComments > 50
ORDER BY BadgeScore DESC, GlobalRank
LIMIT 100;
