-- {"query": "4730.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1439}
WITH PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        pt.Name AS PostType,
        COALESCE(p.Score, 0) AS PostScore,
        COALESCE(p.ViewCount, 0) AS PostViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
),
UserActivitySummary AS (
    SELECT
        pe.OwnerUserId,
        COUNT(pe.PostId) FILTER (WHERE pe.PostId IS NOT NULL) AS TotalPosts,
        SUM(pe.PostScore) AS TotalScore,
        AVG(pe.PostViewCount) AS AvgViewCount,
        SUM(CASE WHEN pe.PostType = 'Question' THEN 1 ELSE 0 END) AS QuestionsCount,
        SUM(CASE WHEN pe.PostType = 'Answer' THEN 1 ELSE 0 END) AS AnswersCount,
        SUM(pe.IsClosed) AS ClosedPostsCount,
        MAX(pe.PostCreationDate) AS LastPostDate,
        (SUM(pe.PostScore) * 1.0 / NULLIF(COUNT(pe.PostId), 0)) AS ScorePerPost
    FROM PostEngagement pe
    GROUP BY pe.OwnerUserId
),
CommentSentiment AS (
    SELECT
        c.PostId,
        AVG(CASE
                WHEN c.Score > 0 THEN 1.0
                WHEN c.Score < 0 THEN -1.0
                ELSE 0.0
            END) AS AvgCommentSentiment
    FROM Comments c
    GROUP BY c.PostId
),
PostHistoryCounts AS (
    SELECT
        ph.PostId,
        COUNT(*) AS PostHistoryCount,
        MAX(ph.Id) AS LastHistoryId
    FROM PostHistory ph
    GROUP BY ph.PostId
),
PostDetails AS (
    SELECT
        pe.PostId,
        pe.OwnerUserId,
        pe.Title,
        pe.PostType,
        pe.PostScore,
        pe.PostViewCount,
        pe.AnswerCount,
        pe.CommentCount,
        pe.FavoriteCount,
        pe.IsClosed,
        cs.AvgCommentSentiment,
        u.Reputation AS OwnerReputation,
        u.Views AS OwnerViews,
        u.UpVotes AS OwnerUpVotes,
        u.DownVotes AS OwnerDownVotes,
        phc.PostHistoryCount,
        CASE
            WHEN ph.PostHistoryTypeId IN (1, 2, 3) THEN 'Initial'
            WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 'Edit'
            WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN 'Rollback'
            WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) THEN 'Moderation'
            ELSE 'Other'
        END AS LastHistoryActionType,
        pe.UserPostRank
    FROM PostEngagement pe
    LEFT JOIN Users u ON pe.OwnerUserId = u.Id
    LEFT JOIN CommentSentiment cs ON pe.PostId = cs.PostId
    LEFT JOIN PostHistory ph ON pe.PostId = ph.PostId
    LEFT JOIN PostHistoryCounts phc ON pe.PostId = phc.PostId
)
SELECT
    pd.PostId,
    pd.Title,
    pd.PostType,
    pd.PostScore,
    pd.PostViewCount,
    pd.AnswerCount,
    pd.CommentCount,
    pd.FavoriteCount,
    pd.IsClosed,
    pd.AvgCommentSentiment,
    pd.OwnerReputation,
    pd.OwnerViews,
    pd.OwnerUpVotes,
    pd.OwnerDownVotes,
    COALESCE(pd.PostHistoryCount, 0) AS PostHistoryCount,
    pd.LastHistoryActionType,
    uas.TotalPosts AS OwnerTotalPosts,
    uas.TotalScore AS OwnerTotalScore,
    uas.AvgViewCount AS OwnerAvgViewCount,
    uas.QuestionsCount AS OwnerQuestionsCount,
    uas.AnswersCount AS OwnerAnswersCount,
    uas.ClosedPostsCount AS OwnerClosedPostsCount,
    CASE
        WHEN uas.ScorePerPost IS NULL THEN 'Low'
        WHEN uas.ScorePerPost > 5 THEN 'High'
        WHEN uas.ScorePerPost >= 1 AND uas.ScorePerPost <= 5 THEN 'Medium'
        ELSE 'Low'
    END AS OwnerScorePerPostCategory,
    CASE WHEN pd.OwnerReputation > 100000 OR COALESCE(uas.TotalPosts,0) > 5000 THEN 'High Potential' ELSE 'Standard' END AS UserPotentialCategory,
    CHARACTER_LENGTH(COALESCE(pd.Title, '')) AS TitleLength,
    SUBSTRING(pd.Title FROM 1 FOR 10) AS TitlePrefix,
    CASE
        WHEN pd.PostScore > (SELECT AVG(COALESCE(p2.Score,0)) FROM Posts p2 WHERE p2.PostTypeId = 1) THEN 'Above Average Score'
        ELSE 'Below Average Score'
    END AS ScoreComparison,
    COALESCE(pl.LinkCount, 0) AS RelatedPostLinks,
    COALESCE(pl.DuplicateCount, 0) AS DuplicateLinks
FROM PostDetails pd
LEFT JOIN UserActivitySummary uas ON pd.OwnerUserId = uas.OwnerUserId
LEFT JOIN (
    SELECT
        PostId,
        SUM(CASE WHEN LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkCount,
        SUM(CASE WHEN LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateCount
    FROM PostLinks
    GROUP BY PostId
) pl ON pd.PostId = pl.PostId
WHERE pd.UserPostRank <= 5
GROUP BY
    pd.PostId,
    pd.Title,
    pd.PostType,
    pd.PostScore,
    pd.PostViewCount,
    pd.AnswerCount,
    pd.CommentCount,
    pd.FavoriteCount,
    pd.IsClosed,
    pd.AvgCommentSentiment,
    pd.OwnerReputation,
    pd.OwnerViews,
    pd.OwnerUpVotes,
    pd.OwnerDownVotes,
    pd.PostHistoryCount,
    pd.LastHistoryActionType,
    uas.TotalPosts,
    uas.TotalScore,
    uas.AvgViewCount,
    uas.QuestionsCount,
    uas.AnswersCount,
    uas.ClosedPostsCount,
    uas.ScorePerPost,
    pd.OwnerReputation, /* repeated for clarity in grouping expressions */
    uas.TotalPosts,     /* repeated */
    pd.Title,           /* for CHARACTER_LENGTH and SUBSTRING usage */
    pl.LinkCount,
    pl.DuplicateCount,
    pd.UserPostRank
ORDER BY pd.OwnerReputation DESC NULLS LAST, pd.PostScore DESC;