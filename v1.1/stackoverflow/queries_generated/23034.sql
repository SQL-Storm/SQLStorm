-- {"query": "23034.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 939} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName
),
BadgeStats AS (
    SELECT 
        UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        STRING_AGG(Name, ', ') AS BadgeNames
    FROM Badges
    GROUP BY UserId
),
VoteAnalysis AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        COALESCE(SUM(BountyAmount), 0) AS TotalBounty
    FROM Votes v
    WHERE v.CreationDate > '2020-01-01'
    GROUP BY v.PostId
    HAVING SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) > 10
),
ComplexPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.Tags,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
        CASE 
            WHEN p.ClosedDate IS NULL THEN 'Open' 
            ELSE 'Closed' 
        END AS Status,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore
    FROM Posts p
    WHERE p.ViewCount > 1000 OR p.FavoriteCount IS NOT NULL
),
MergedData AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.PostCount,
        us.QuestionCount,
        us.AnswerCount,
        us.AvgPostScore,
        us.LastPostDate,
        us.ReputationRank,
        bs.TotalBadges,
        bs.GoldBadges,
        bs.BadgeNames,
        SUM(va.Upvotes) AS TotalUpvotes,
        SUM(va.Downvotes) AS TotalDownvotes,
        AVG(cp.PositiveComments) AS AvgPositiveComments
    FROM UserStats us
    LEFT OUTER JOIN BadgeStats bs ON us.UserId = bs.UserId
    LEFT OUTER JOIN Posts po ON us.UserId = po.OwnerUserId
    LEFT OUTER JOIN VoteAnalysis va ON po.Id = va.PostId
    LEFT OUTER JOIN ComplexPosts cp ON po.Id = cp.Id
    WHERE us.Reputation > (SELECT AVG(Reputation) FROM Users WHERE Reputation > 0)
      AND EXISTS (SELECT 1 FROM Tags t WHERE t.Count > 100 AND po.Tags LIKE '%' || t.TagName || '%')
    GROUP BY us.UserId, us.DisplayName, us.Reputation, us.PostCount, us.QuestionCount, us.AnswerCount, us.AvgPostScore, us.LastPostDate, us.ReputationRank, bs.TotalBadges, bs.GoldBadges, bs.BadgeNames
)
SELECT * FROM MergedData
UNION ALL
SELECT 
    NULL AS UserId,
    'Summary' AS DisplayName,
    SUM(Reputation) AS Reputation,
    SUM(PostCount) AS PostCount,
    SUM(QuestionCount) AS QuestionCount,
    SUM(AnswerCount) AS AnswerCount,
    AVG(AvgPostScore) AS AvgPostScore,
    MAX(LastPostDate) AS LastPostDate,
    NULL AS ReputationRank,
    SUM(TotalBadges) AS TotalBadges,
    SUM(GoldBadges) AS GoldBadges,
    NULL AS BadgeNames,
    SUM(TotalUpvotes) AS TotalUpvotes,
    SUM(TotalDownvotes) AS TotalDownvotes,
    AVG(AvgPositiveComments) AS AvgPositiveComments
FROM MergedData
ORDER BY Reputation DESC;