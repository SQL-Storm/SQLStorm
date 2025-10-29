-- {"query": "4774.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 942} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        COUNT(c.Id) AS CommentCount,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.FavoriteCount > 1000 THEN 'Highly Favorited'
            ELSE 'Active'
        END AS PostStatus,
        LOWER(p.Tags) AS NormalizedTags
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Votes AS v ON p.Id = v.PostId AND v.VoteTypeId = 2
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    WHERE p.OwnerUserId IS NOT NULL
      AND p.CreationDate > '2023-01-01'
      AND p.Title IS NOT NULL
      AND LENGTH(p.Title) > 5
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate, pt.Name, p.ClosedDate, p.FavoriteCount
),
UserPostEngagement AS (
    SELECT
        rp.OwnerUserId,
        COUNT(DISTINCT rp.PostId) AS TotalPosts,
        SUM(rp.UpVoteCount) AS TotalUpVotes,
        AVG(rp.AvgUserScore) AS AverageUserPostScore,
        MAX(rp.PostRank) AS MaxPostRank,
        STRING_AGG(rp.PostStatus, ', ') WITHIN GROUP (ORDER BY rp.PostRank) AS DistinctPostStatuses,
        COUNT(DISTINCT rp.NormalizedTags) AS DistinctTagCount
    FROM RankedPosts AS rp
    WHERE rp.PostRank <= 10
    GROUP BY rp.OwnerUserId
    HAVING COUNT(DISTINCT rp.PostId) > 2
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(up.TotalPosts, 0) AS UserTotalPosts,
    COALESCE(up.TotalUpVotes, 0) AS UserTotalUpVotes,
    COALESCE(up.AverageUserPostScore, 0.0) AS UserAvgScore,
    up.DistinctPostStatuses,
    CASE
        WHEN u.CreationDate < '2010-01-01' THEN 'Early Adopter'
        WHEN u.Views > 100000 THEN 'High Visibility'
        ELSE 'Standard User'
    END AS UserTier,
    CASE
        WHEN EXISTS (SELECT 1 FROM Badges AS b WHERE b.UserId = u.Id AND b.Name LIKE '%Expert%') THEN 'Badge Holder'
        ELSE 'No Expert Badge'
    END AS ExpertBadgeStatus,
    CASE
        WHEN up.DistinctTagCount > 5 THEN 'Multi-Talented'
        ELSE 'Focused'
    END AS UserTagFocus,
    COALESCE(up.MaxPostRank, 999) AS HighestPostRank,
    (
        SELECT COUNT(*)
        FROM Comments AS c
        WHERE c.UserId = u.Id
          AND c.CreationDate BETWEEN u.CreationDate AND DATE_ADD(u.CreationDate, INTERVAL 1 YEAR)
    ) AS FirstYearCommentCount,
    CASE WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website' ELSE 'Has Website' END AS WebsitePresence
FROM Users AS u
LEFT JOIN UserPostEngagement AS up ON u.Id = up.OwnerUserId
WHERE u.Id IN (
    SELECT OwnerUserId
    FROM RankedPosts
    WHERE PostRank <= 5
)
ORDER BY u.Reputation DESC, up.TotalUpVotes DESC
LIMIT 100;
