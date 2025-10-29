-- {"query": "4352.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1057}
WITH RankedPosts AS (
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
        p.CommunityOwnedDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_by_type,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousDayScore,
        SUM(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS RollingWeeklyScore
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year') AND p.Score > -5
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '6 months')
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
HighReputationUsers AS (
    SELECT Id, DisplayName
    FROM Users
    WHERE Reputation > 50000
),
CommentsOnQuestions AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCountOnPost,
        MAX(c.CreationDate) AS LastCommentDateOnPost
    FROM Comments c
    JOIN Posts p ON c.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY c.PostId
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.rn_by_type,
    rp.PreviousDayScore,
    rp.RollingWeeklyScore,
    COALESCE(upa.TotalPostsCreated, 0) AS UserTotalPosts,
    COALESCE(upa.QuestionsAsked, 0) AS QuestionsAsked,
    COALESCE(upa.AnswersGiven, 0) AS AnswersGiven,
    upa.AvgPostScore,
    CASE WHEN rp.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
    CASE WHEN hr.Id IS NOT NULL THEN 'HighRep' ELSE 'Regular' END AS UserReputationLevel,
    CASE WHEN COALESCE(cqo.CommentCountOnPost, 0) > 10 THEN 'HighCommentActivity' ELSE 'LowCommentActivity' END AS CommentActivityLevel,
    LOWER(SUBSTR(rp.PostTypeName, 1, 1)) || UPPER(SUBSTR(rp.PostTypeName, 2)) AS FormattedPostTypeName,
    CASE
        WHEN rp.PostScore > 100 THEN 'Very High Score'
        WHEN rp.PostScore > 50 THEN 'High Score'
        WHEN rp.PostScore > 10 THEN 'Medium Score'
        ELSE 'Low Score'
    END AS ScoreCategory,
    upa.LastPostDate AS UserLastPostDate,
    cqo.LastCommentDateOnPost,
    CASE
        WHEN upa.UserCreationDate < (cast('2024-10-01' as date) - INTERVAL '5 years') THEN 'Veteran'
        WHEN upa.UserCreationDate < (cast('2024-10-01' as date) - INTERVAL '1 year') THEN 'Established'
        ELSE 'New'
    END AS UserTenure
FROM RankedPosts rp
LEFT JOIN UserPostActivity upa ON rp.OwnerUserId = upa.UserId
LEFT JOIN HighReputationUsers hr ON rp.OwnerUserId = hr.Id
LEFT JOIN CommentsOnQuestions cqo ON rp.PostId = cqo.PostId
WHERE rp.rn_by_type <= 1000
ORDER BY rp.PostCreationDate DESC
LIMIT 100;