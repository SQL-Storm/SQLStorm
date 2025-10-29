-- {"query": "4078.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2574} 
WITH CTE_PostInteractions AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.CommentCount,
        p.FavoriteCount,
        p.AnswerCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        COUNT(DISTINCT c.Id) AS NumberOfComments,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) AS FavoriteVoteCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.CommentCount, p.FavoriteCount, p.AnswerCount, p.ClosedDate, pt.Name
),
CTE_UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT ph.Id) AS PostHistoryCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(CASE WHEN b.Class = 1 THEN b.Date ELSE NULL END) AS GoldBadgeDate,
        MIN(CASE WHEN b.Class = 3 THEN b.Date ELSE NULL END) AS BronzeBadgeDate
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
),
CTE_PostQualityMetrics AS (
    SELECT
        pi.PostId,
        pi.PostTypeName,
        pi.PostScore,
        pi.NumberOfComments,
        pi.UpVoteCount,
        pi.DownVoteCount,
        pi.FavoriteVoteCount,
        CASE
            WHEN pi.PostScore > 0 THEN 'Positive'
            WHEN pi.PostScore < 0 THEN 'Negative'
            ELSE 'Neutral'
        END AS ScoreCategory,
        CASE
            WHEN pi.PostTypeId = 1 AND pi.AnswerCount IS NULL THEN 'No AnswerCount'
            WHEN pi.PostTypeId = 1 AND pi.AnswerCount = 0 THEN 'Zero Answers'
            WHEN pi.PostTypeId = 1 AND pi.AnswerCount > 0 THEN 'Has Answers'
            ELSE 'N/A'
        END AS AnswerStatus,
        DENSE_RANK() OVER (ORDER BY pi.PostScore DESC, pi.FavoriteVoteCount DESC) AS PostRankByScoreAndFavorites,
        ROW_NUMBER() OVER (PARTITION BY pi.PostTypeId ORDER BY pi.CreationDate DESC) AS RecentPostNumber
    FROM CTE_PostInteractions pi
),
CTE_UserContribution AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.PostHistoryCount,
        ua.BadgeCount,
        COALESCE(ua.GoldBadgeDate, ua.BronzeBadgeDate, ua.UserCreationDate) AS FirstSignificantDate,
        ua.Reputation * 1.0 / NULLIF(ua.UserViews, 0) AS ReputationPerViewRatio,
        CASE
            WHEN ua.UserUpVotes > ua.UserDownVotes * 10 THEN 'Highly Valued Contributor'
            WHEN ua.UserUpVotes < ua.UserDownVotes / 5 THEN 'Frequently Downvoted'
            ELSE 'Balanced Contributor'
        END AS ContributionProfile
    FROM CTE_UserActivity ua
    WHERE ua.Reputation > 100
)
SELECT
    'BenchmarkQuery' AS QueryName,
    cpi.PostId,
    cpi.PostTypeName,
    cpi.PostScore,
    cpi.NumberOfComments,
    cpi.UpVoteCount,
    cpi.DownVoteCount,
    cpi.FavoriteVoteCount,
    cpi.ScoreCategory,
    cpi.AnswerStatus,
    cpi.PostRankByScoreAndFavorites,
    cpi.RecentPostNumber,
    cuc.UserId,
    cuc.DisplayName,
    cuc.Reputation,
    cuc.PostHistoryCount,
    cuc.BadgeCount,
    cuc.FirstSignificantDate,
    cuc.ReputationPerViewRatio,
    cuc.ContributionProfile,
    CASE
        WHEN cpi.PostScore > (SELECT AVG(PostScore) FROM CTE_PostInteractions) THEN 'Above Average Score'
        ELSE 'Below Average Score'
    END AS ScoreRelativeToAverage,
    CASE
        WHEN cpi.PostTypeName = 'Question' AND cpi.PostScore > 50 AND cpi.FavoriteVoteCount > 10 AND cpi.NumberOfComments > 5 THEN 'High Engagement Question'
        WHEN cpi.PostTypeName = 'Answer' AND cpi.PostScore > 20 AND cpi.UpVoteCount > 15 THEN 'High Engagement Answer'
        ELSE 'Standard Engagement'
    END AS EngagementLevel,
    UPPER(SUBSTRING(cuc.DisplayName FROM 1 FOR 3)) AS Initials,
    CASE
        WHEN cpi.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END AS PostStatus,
    STRFTIME('%Y-%m', cpi.PostCreationDate) AS PostYearMonth,
    cuc.Reputation AS UserReputationForJoin,
    cpi.PostScore AS PostScoreForJoin,
    cuc.BadgeCount + cpi.NumberOfComments AS CombinedActivityMetric
FROM CTE_PostQualityMetrics cpi
LEFT JOIN CTE_UserContribution cuc
    ON cpi.OwnerUserId = cuc.UserId
WHERE cpi.PostScore > -5 -- Filter out very low scoring posts
  AND cpi.PostId % 10 = 0 -- Sample posts for performance
  AND cuc.Reputation > 500 -- Focus on more established users
UNION ALL
SELECT
    'ComplementaryData' AS QueryName,
    p.Id AS PostId,
    pt.Name AS PostTypeName,
    p.Score AS PostScore,
    COUNT(DISTINCT c.Id) AS NumberOfComments,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) AS FavoriteVoteCount,
    CASE
        WHEN p.Score > 0 THEN 'Positive'
        WHEN p.Score < 0 THEN 'Negative'
        ELSE 'Neutral'
    END AS ScoreCategory,
    CASE
        WHEN p.PostTypeId = 1 AND p.AnswerCount IS NULL THEN 'No AnswerCount'
        WHEN p.PostTypeId = 1 AND p.AnswerCount = 0 THEN 'Zero Answers'
        WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Has Answers'
        ELSE 'N/A'
    END AS AnswerStatus,
    DENSE_RANK() OVER (ORDER BY p.Score DESC, COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) DESC) AS PostRankByScoreAndFavorites,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS RecentPostNumber,
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    (SELECT COUNT(*) FROM PostHistory WHERE UserId = u.Id) AS PostHistoryCount,
    (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id) AS BadgeCount,
    u.CreationDate AS FirstSignificantDate,
    u.Reputation * 1.0 / NULLIF(u.Views, 0) AS ReputationPerViewRatio,
    CASE
        WHEN u.UpVotes > u.DownVotes * 10 THEN 'Highly Valued Contributor'
        WHEN u.UpVotes < u.DownVotes / 5 THEN 'Frequently Downvoted'
        ELSE 'Balanced Contributor'
    END AS ContributionProfile,
    CASE
        WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId IN (1,2)) THEN 'Above Average Score'
        ELSE 'Below Average Score'
    END AS ScoreRelativeToAverage,
    CASE
        WHEN pt.Name = 'Question' AND p.Score > 50 AND COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) > 10 AND COUNT(DISTINCT c.Id) > 5 THEN 'High Engagement Question'
        WHEN pt.Name = 'Answer' AND p.Score > 20 AND SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 15 THEN 'High Engagement Answer'
        ELSE 'Standard Engagement'
    END AS EngagementLevel,
    UPPER(SUBSTRING(u.DisplayName FROM 1 FOR 3)) AS Initials,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END AS PostStatus,
    STRFTIME('%Y-%m', p.CreationDate) AS PostYearMonth,
    u.Reputation AS UserReputationForJoin,
    p.Score AS PostScoreForJoin,
    (SELECT COUNT(*) FROM PostHistory WHERE UserId = u.Id) + COUNT(DISTINCT c.Id) AS CombinedActivityMetric
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId IN (1, 2)
  AND p.Score < 0 -- Select posts with negative scores
  AND u.Reputation < 100 -- Focus on new users for comparison
GROUP BY
    p.Id, pt.Name, p.Score, p.PostTypeId, p.AnswerCount, p.ClosedDate, p.CreationDate,
    u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
HAVING COUNT(DISTINCT c.Id) > 0 OR SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) > 0 -- Posts with comments or downvotes
ORDER BY PostScore DESC, FavoriteVoteCount DESC;