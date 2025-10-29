WITH RelevantPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        CASE WHEN p.PostTypeId = 1 THEN SUBSTRING(p.Tags FROM 2 FOR POSITION('>' IN SUBSTRING(p.Tags FROM 2)) - 1) ELSE NULL END AS PrimaryTag,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostSequence,
        p.CommunityOwnedDate
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT ph.PostId) AS PostHistoryCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 ELSE 0 END) AS BodyEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId = 1 THEN 1 ELSE 0 END) AS TitleEdits,
        MAX(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS HasUpvoted,
        MAX(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS HasDownvoted
    FROM Users AS u
    LEFT JOIN PostHistory AS ph ON u.Id = ph.UserId
    LEFT JOIN Votes AS v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
RankedAnswers AS (
    SELECT
        rp.PostId,
        rp.OwnerUserId,
        rp.PostCreationDate,
        rp.PostScore,
        rp.PostSequence,
        ROW_NUMBER() OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.PostScore DESC, rp.PostCreationDate ASC) AS AnswerRank
    FROM RelevantPosts AS rp
    WHERE rp.PostTypeId = 2
),
UserQualityScore AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.UserCreationDate,
        ua.PostHistoryCount,
        ua.BodyEdits,
        ua.TitleEdits,
        ua.HasUpvoted,
        ua.HasDownvoted,
        COALESCE(SUM(ra.PostScore), 0) AS TotalAnswerScore,
        COALESCE(AVG(ra.PostScore), 0) AS AverageAnswerScore,
        COALESCE(SUM(CASE WHEN ra.AnswerRank = 1 THEN 1 ELSE 0 END), 0) AS AcceptedAnswerCount,
        CASE
            WHEN ua.Reputation > 10000 THEN 'High'
            WHEN ua.Reputation > 1000 THEN 'Medium'
            ELSE 'Low'
        END AS ReputationTier,
        LENGTH(ua.DisplayName) AS DisplayNameLength,
        (ua.BodyEdits * 5) + (ua.TitleEdits * 3) AS EditImpact
    FROM UserActivity AS ua
    LEFT JOIN RankedAnswers AS ra ON ua.UserId = ra.OwnerUserId
    GROUP BY ua.UserId, ua.DisplayName, ua.Reputation, ua.UserCreationDate, ua.PostHistoryCount, ua.BodyEdits, ua.TitleEdits, ua.HasUpvoted, ua.HasDownvoted
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.PrimaryTag,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.PostCreationDate > (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '7 day') THEN 'Recent'
        ELSE 'Active'
    END AS PostStatus,
    uqs.DisplayName AS OwnerDisplayName,
    uqs.Reputation AS OwnerReputation,
    uqs.UserCreationDate AS OwnerCreationDate,
    uqs.ReputationTier,
    uqs.EditImpact,
    uqs.TotalAnswerScore,
    uqs.AverageAnswerScore,
    uqs.AcceptedAnswerCount,
    (rp.PostScore - rp.PreviousPostScore) AS ScoreDifference,
    rp.PostSequence,
    (uqs.DisplayName || ' (' || uqs.Reputation || ')') AS OwnerInfo,
    CASE
        WHEN rp.PostTypeId = 1 AND rp.AnswerCount > 50 THEN 'High Engagement Question'
        WHEN rp.PostTypeId = 2 AND rp.PostScore > 10 THEN 'Highly Scored Answer'
        ELSE 'Standard Post'
    END AS PostEngagementLevel,
    (COALESCE(uqs.HasUpvoted, 0) | COALESCE(uqs.HasDownvoted, 0)) AS HasVoted,
    rp.PostScore * rp.PostViewCount AS ScoreViewProduct
FROM RelevantPosts AS rp
INNER JOIN UserQualityScore AS uqs ON rp.OwnerUserId = uqs.UserId
WHERE rp.PostSequence <= 10
  AND rp.PostScore > -5
  AND uqs.DisplayName IS NOT NULL
  AND rp.PrimaryTag IN ('sql', 'performance', 'database', 'query', 'optimization')
UNION ALL
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.PrimaryTag,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.PostCreationDate > (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '7 day') THEN 'Recent'
        ELSE 'Active'
    END AS PostStatus,
    'Community' AS OwnerDisplayName,
    100000 AS OwnerReputation,
    rp.CommunityOwnedDate AS OwnerCreationDate,
    'High' AS ReputationTier,
    0 AS EditImpact,
    0 AS TotalAnswerScore,
    0 AS AverageAnswerScore,
    0 AS AcceptedAnswerCount,
    (rp.PostScore - rp.PreviousPostScore) AS ScoreDifference,
    rp.PostSequence,
    'Community User (100000)' AS OwnerInfo,
    'Community Owned Post' AS PostEngagementLevel,
    0 AS HasVoted,
    rp.PostScore * rp.PostViewCount AS ScoreViewProduct
FROM RelevantPosts AS rp
WHERE rp.OwnerUserId = -1
  AND rp.PostSequence <= 5
  AND rp.PostScore > 0
ORDER BY PostCreationDate DESC
LIMIT 100;