-- {"query": "4071.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1351}
WITH RecentPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRankForUser
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')
),
UserActivity AS (
    SELECT
        UserId,
        COUNT(Id) AS TotalComments,
        SUM(CASE WHEN Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreComments,
        SUM(CASE WHEN Score < 0 THEN 1 ELSE 0 END) AS NegativeScoreComments,
        COUNT(DISTINCT PostId) AS DistinctPostsCommentedOn,
        MAX(CreationDate) AS LastCommentDate
    FROM Comments
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
TopUsers AS (
    SELECT
        Id AS UserId,
        DisplayName,
        Reputation,
        CreationDate,
        Views,
        UpVotes,
        DownVotes,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS UserReputationRank
    FROM Users
    WHERE CreationDate >= (cast('2024-10-01' as date) - INTERVAL '5 years')
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        COUNT(pl.RelatedPostId) AS LinkedPostsCount,
        SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateLinks,
        SUM(CASE WHEN lt.Name = 'Linked' THEN 1 ELSE 0 END) AS StandardLinks
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.IsClosed,
    COALESCE(tu.Reputation, 0) AS OwnerReputation,
    COALESCE(ua.TotalComments, 0) AS OwnerTotalComments,
    COALESCE(ua.PositiveScoreComments, 0) AS OwnerPositiveScoreComments,
    COALESCE(ua.NegativeScoreComments, 0) AS OwnerNegativeScoreComments,
    COALESCE(pla.LinkedPostsCount, 0) AS PostLinkedCount,
    COALESCE(pla.DuplicateLinks, 0) AS PostDuplicateLinks,
    COALESCE(pla.StandardLinks, 0) AS PostStandardLinks,
    CASE
        WHEN rp.PostScore > 100 AND rp.AnswerCount > 10 THEN 'High Engagement Question'
        WHEN rp.PostScore < -5 AND rp.IsClosed = 1 THEN 'Negatively Scored Closed Post'
        WHEN rp.FavoriteCount > 50 THEN 'Highly Favorited Post'
        WHEN rp.PostRankForUser <= 5 THEN 'Top 5 Post by User'
        ELSE 'Standard Post'
    END AS PostClassification,
    tu.UserReputationRank,
    (rp.PostViewCount * 1.0 / NULLIF(rp.PostScore + 1, 0)) AS ViewScoreRatio,
    RPAD(LEFT(COALESCE(u.AboutMe, 'No Bio'), 50), 50, ' ') AS TruncatedUserBio,
    CASE
        WHEN rp.PostCreationDate BETWEEN (cast('2024-10-01' as date) - INTERVAL '7 days') AND cast('2024-10-01' as date) THEN 'Last Week'
        WHEN rp.PostCreationDate BETWEEN (cast('2024-10-01' as date) - INTERVAL '30 days') AND (cast('2024-10-01' as date) - INTERVAL '7 days') THEN '3-4 Weeks Ago'
        ELSE 'Older'
    END AS PostAgeGroup,
    SUM(rp.PostScore) OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.PostCreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningUserScore,
    CASE
        WHEN rp.OwnerUserId IS NULL OR COALESCE(tu.UserReputationRank, 99999) > 1000 THEN 'New/Low Rep User'
        WHEN COALESCE(tu.UserReputationRank, 99999) <= 100 THEN 'Top 100 Rep User'
        ELSE 'Mid-Tier User'
    END AS UserTier,
    CASE
        WHEN rp.PostTypeName IN ('Question', 'Answer') AND rp.PostScore > 0 THEN LENGTH(rp.OwnerDisplayName)
        ELSE 0
    END AS DisplayNameLengthForValue,
    COALESCE(rp.PostViewCount, 0) + COALESCE(rp.AnswerCount, 0) * 10 + COALESCE(rp.CommentCount, 0) * 5 AS CompositeEngagementScore
FROM RecentPosts rp
LEFT JOIN TopUsers tu ON rp.OwnerUserId = tu.UserId
LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN PostLinkAnalysis pla ON rp.PostId = pla.PostId
LEFT JOIN Users u ON rp.OwnerUserId = u.Id
WHERE rp.PostCreationDate >= (cast('2024-10-01' as date) - INTERVAL '6 months')
  AND (rp.PostTypeName = 'Question' OR rp.PostTypeName = 'Answer')
  AND rp.PostScore >= -10
GROUP BY
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.IsClosed,
    tu.Reputation,
    ua.TotalComments,
    ua.PositiveScoreComments,
    ua.NegativeScoreComments,
    pla.LinkedPostsCount,
    pla.DuplicateLinks,
    pla.StandardLinks,
    rp.PostRankForUser,
    tu.UserReputationRank,
    u.AboutMe,
    rp.OwnerUserId,
    rp.PostTypeId
ORDER BY rp.PostCreationDate DESC
LIMIT 1000;