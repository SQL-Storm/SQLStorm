-- {"query": "4276.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1976}
WITH PostSummary AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_post_type,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS avg_score_by_type,
        CASE
            WHEN p.Score > 0 THEN 'Positive'
            WHEN p.Score < 0 THEN 'Negative'
            ELSE 'Zero'
        END AS ScoreCategory,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
),
CommentStats AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCountOnPost,
        SUM(c.Score) AS TotalCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
VoteDistribution AS (
    SELECT
        v.PostId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVoteCount,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVoteCount,
        COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 END) AS FavoriteVoteCount
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY v.PostId
),
AllPostData AS (
    SELECT
        ps.PostId,
        ps.PostTypeId,
        ps.PostTypeName,
        ps.OwnerUserId,
        ps.OwnerDisplayName,
        ps.PostCreationDate,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.ClosedDate,
        ps.rn_post_type,
        ps.avg_score_by_type,
        ps.ScoreCategory,
        ps.PreviousPostScore,
        COALESCE(cs.CommentCountOnPost, 0) AS TotalComments,
        COALESCE(cs.TotalCommentScore, 0) AS CommentsScoreSum,
        COALESCE(vd.UpVoteCount, 0) AS UpVotes,
        COALESCE(vd.DownVoteCount, 0) AS DownVotes,
        COALESCE(vd.FavoriteVoteCount, 0) AS Favorites
    FROM PostSummary ps
    LEFT JOIN CommentStats cs ON ps.PostId = cs.PostId
    LEFT JOIN VoteDistribution vd ON ps.PostId = vd.PostId
),
RankedPostData AS (
    SELECT
        apd.PostId,
        apd.PostTypeId,
        apd.PostTypeName,
        apd.OwnerUserId,
        apd.OwnerDisplayName,
        apd.PostCreationDate,
        apd.Score,
        apd.ViewCount,
        apd.AnswerCount,
        apd.CommentCount,
        apd.FavoriteCount,
        apd.ClosedDate,
        apd.rn_post_type,
        apd.avg_score_by_type,
        apd.ScoreCategory,
        apd.PreviousPostScore,
        apd.TotalComments,
        apd.CommentsScoreSum,
        apd.UpVotes,
        apd.DownVotes,
        apd.Favorites,
        RANK() OVER (ORDER BY apd.Score DESC, apd.PostCreationDate ASC) AS ScoreRank,
        DENSE_RANK() OVER (ORDER BY apd.ViewCount DESC) AS ViewRank,
        CASE
            WHEN apd.AnswerCount > 0 THEN CAST(apd.Score AS DOUBLE PRECISION) / apd.AnswerCount
            ELSE NULL
        END AS ScorePerAnswer,
        UPPER(SUBSTRING(apd.OwnerDisplayName FROM 1 FOR 1)) AS OwnerInitial,
        CASE WHEN apd.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus
    FROM AllPostData apd
    WHERE apd.PostTypeId = 1
),
MostActiveUsers AS (
    SELECT
        OwnerUserId AS UserId,
        COUNT(Id) AS PostCount,
        SUM(Score) AS TotalScore
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
    ORDER BY PostCount DESC
    LIMIT 50
),
UserActivityCorrelation AS (
    SELECT
        rp.PostId,
        rp.OwnerUserId,
        mau.PostCount AS OwnerPostCount,
        mau.TotalScore AS OwnerTotalScore,
        rp.Score AS PostScore,
        rp.ViewCount AS PostViewCount,
        CASE
            WHEN rp.OwnerDisplayName LIKE '%admin%' THEN 1
            WHEN rp.OwnerDisplayName LIKE '%moderator%' THEN 2
            ELSE 0
        END AS UserTypeFlag
    FROM RankedPostData rp
    JOIN MostActiveUsers mau ON rp.OwnerUserId = mau.UserId
    WHERE rp.OwnerUserId IS NOT NULL
)
SELECT
    u.DisplayName AS FinalUserDisplayName,
    u.Reputation,
    u.Views AS UserTotalViews,
    u.UpVotes AS UserTotalUpVotes,
    u.DownVotes AS UserTotalDownVotes,
    p.PostId,
    NULL AS PostTitle,
    p.PostTypeName,
    p.PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    p.AnswerCount AS PostAnswerCount,
    p.CommentsScoreSum AS TotalCommentScoreSum,
    p.UpVotes AS TotalUpVotes,
    p.DownVotes AS TotalDownVotes,
    p.Favorites AS TotalFavorites,
    p.ScoreRank,
    p.ViewRank,
    p.ScorePerAnswer,
    p.OwnerInitial,
    p.PostStatus,
    p.avg_score_by_type,
    p.PreviousPostScore,
    p.OwnerDisplayName,
    uac.UserTypeFlag,
    CASE WHEN p.PostTypeName = 'Question' AND p.ClosedDate IS NULL AND p.PostCreationDate < (CAST('2024-10-01' AS date) - INTERVAL '365 days') AND p.Score > 100 THEN 'High Performing Old Question' ELSE 'Standard Post' END AS PerformanceCategory,
    CASE
        WHEN p.OwnerDisplayName IS NULL THEN 'Anonymous'
        ELSE 'Registered'
    END AS OwnerPresence,
    EXTRACT(YEAR FROM p.PostCreationDate) AS PostYear,
    UPPER(REPLACE(COALESCE(p.OwnerDisplayName, 'N/A'), ' ', '_')) AS FormattedOwnerName,
    CASE WHEN p.Score > p.avg_score_by_type * 1.5 THEN 'Above Average Performer' ELSE 'Average or Below Performer' END AS PerformanceVsAverage,
    CASE
        WHEN p.PostCreationDate BETWEEN (CAST('2024-10-01' AS date) - INTERVAL '7 days') AND CAST('2024-10-01' AS date) THEN 'Last Week'
        WHEN p.PostCreationDate BETWEEN (CAST('2024-10-01' AS date) - INTERVAL '30 days') AND (CAST('2024-10-01' AS date) - INTERVAL '7 days') THEN 'Last Month'
        ELSE 'Older'
    END AS PostAgeGroup,
    COALESCE(uac.OwnerPostCount, 0) AS OwnerTotalPostCount,
    COALESCE(uac.OwnerTotalScore, 0) AS OwnerTotalScoreSum,
    CASE WHEN p.Score > 0 AND p.ScorePerAnswer IS NOT NULL AND p.ScorePerAnswer > 5 THEN 1 ELSE 0 END AS HighScorePerAnswerIndicator,
    (p.UpVotes - p.DownVotes) AS NetVotes,
    CASE WHEN p.ViewCount = 0 THEN NULL ELSE CAST(p.Score AS DOUBLE PRECISION) / p.ViewCount END AS ScorePerView,
    CASE WHEN POSITION('?' IN COALESCE(NULL, '')) > 0 THEN 'Is Question' ELSE 'Not a Question' END AS TitleFormat,
    COALESCE(p.OwnerDisplayName, 'Community') AS DisplayNameOrCommunity,
    0 AS TitleLength,
    SUBSTRING(COALESCE(NULL, '') FROM 1 FOR 50) AS TruncatedTitle,
    CASE WHEN p.OwnerUserId = -1 THEN 'Community User' ELSE 'Regular User' END AS OwnerType
FROM RankedPostData p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN UserActivityCorrelation uac ON p.PostId = uac.PostId
WHERE p.ScoreRank <= 1000
  AND p.ViewRank <= 500
  AND COALESCE(uac.OwnerPostCount, 0) >= 10
ORDER BY p.ScoreRank, p.ViewRank DESC
LIMIT 100;