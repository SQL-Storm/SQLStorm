-- {"query": "4570.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2045} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.FavoriteCount AS PostFavoriteCount,
        p.AnswerCount AS PostAnswerCount,
        p.CommentCount AS PostCommentCount,
        p.ClosedDate,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRankByOwner,
        LAG(p.Score, 1, 0) OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
        LEAD(p.Score, 1, 0) OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScore,
        AVG(CAST(p.Score AS FLOAT)) OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) AS RollingAvgScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT ph.Id) AS PostHistoryCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 ELSE 0 END) AS BodyEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS TagEdits,
        MAX(ph.CreationDate) AS LastHistoryDate
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes
),
CommentActivity AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        AVG(CAST(c.Score AS FLOAT)) AS AvgCommentScore,
        SUM(CASE WHEN c.Score < 0 THEN 1 ELSE 0 END) AS NegativeCommentCount
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
PostAndUserStats AS (
    SELECT
        rp.PostId,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.PostCreationDate,
        rp.PostScore,
        rp.PostViewCount,
        rp.PostFavoriteCount,
        rp.PostAnswerCount,
        rp.PostCommentCount,
        rp.ClosedDate,
        rp.PostRankByOwner,
        rp.PreviousPostScore,
        rp.NextPostScore,
        rp.RollingAvgScore,
        ua.Reputation AS OwnerReputation,
        ua.UserCreationDate AS OwnerCreationDate,
        ua.LastAccessDate AS OwnerLastAccessDate,
        ua.UserViews AS OwnerUserViews,
        ua.UserUpVotes AS OwnerUserUpVotes,
        ua.UserDownVotes AS OwnerUserDownVotes,
        COALESCE(ca.CommentCount, 0) AS OwnerCommentCount,
        COALESCE(ca.AvgCommentScore, 0.0) AS OwnerAvgCommentScore,
        COALESCE(ca.NegativeCommentCount, 0) AS OwnerNegativeCommentCount,
        ua.PostHistoryCount AS OwnerPostHistoryCount,
        ua.BodyEdits AS OwnerBodyEdits,
        ua.TagEdits AS OwnerTagEdits,
        ua.LastHistoryDate AS OwnerLastHistoryDate,
        CASE
            WHEN rp.PostScore > 100 AND rp.PostAnswerCount > 5 THEN 'High Engagement Question'
            WHEN rp.PostScore < 0 THEN 'Low Score Post'
            WHEN rp.ClosedDate IS NOT NULL THEN 'Closed Post'
            ELSE 'Standard Post'
        END AS PostStatusCategory,
        DATEDIFF(day, ua.UserCreationDate, rp.PostCreationDate) AS DaysSinceUserCreation,
        rp.PostScore - rp.PreviousPostScore AS ScoreDifferenceFromPrevious,
        rp.NextPostScore - rp.PostScore AS ScoreDifferenceToNext,
        CASE WHEN rp.PostScore > rp.PreviousPostScore THEN 'Improved' WHEN rp.PostScore < rp.PreviousPostScore THEN 'Declined' ELSE 'Stable' END AS ScoreTrend,
        RPAD('Score:', 10, '-') AS ScoreLabel,
        SUBSTRING(ua.DisplayName, 1, 3) AS UserInitial,
        CONCAT(ua.DisplayName, ' (Rep: ', ua.Reputation, ')') AS UserDisplayNameWithRep,
        IIF(ua.WebsiteUrl IS NULL OR ua.WebsiteUrl = '', 'No Website', 'Has Website') AS WebsiteStatus
    FROM RankedPosts rp
    JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
    LEFT JOIN CommentActivity ca ON rp.OwnerUserId = ca.UserId
)
SELECT
    pus.PostId,
    pus.PostTypeId,
    pus.OwnerUserId,
    pus.PostCreationDate,
    pus.PostScore,
    pus.PostViewCount,
    pus.PostFavoriteCount,
    pus.PostAnswerCount,
    pus.PostCommentCount,
    pus.ClosedDate,
    pus.PostRankByOwner,
    pus.PreviousPostScore,
    pus.NextPostScore,
    pus.RollingAvgScore,
    pus.OwnerReputation,
    pus.OwnerCreationDate,
    pus.OwnerLastAccessDate,
    pus.OwnerUserViews,
    pus.OwnerUserUpVotes,
    pus.OwnerUserDownVotes,
    pus.OwnerCommentCount,
    pus.OwnerAvgCommentScore,
    pus.OwnerNegativeCommentCount,
    pus.OwnerPostHistoryCount,
    pus.OwnerBodyEdits,
    pus.OwnerTagEdits,
    pus.OwnerLastHistoryDate,
    pus.PostStatusCategory,
    pus.DaysSinceUserCreation,
    pus.ScoreDifferenceFromPrevious,
    pus.ScoreDifferenceToNext,
    pus.ScoreTrend,
    pus.ScoreLabel,
    pus.UserInitial,
    pus.UserDisplayNameWithRep,
    pus.WebsiteStatus,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = pus.OwnerUserId AND p2.Score > pus.PostScore) AS HigherScoringPostsByOwner,
    (SELECT TOP 1 pt.Name FROM PostTypes pt WHERE pt.Id = pus.PostTypeId) AS PostTypeName,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = pus.PostId AND pl.LinkTypeId = 3) AS DuplicateLinkCount
FROM PostAndUserStats pus
WHERE pus.PostRankByOwner <= 50
UNION ALL
SELECT
    NULL AS PostId,
    NULL AS PostTypeId,
    NULL AS OwnerUserId,
    NULL AS PostCreationDate,
    NULL AS PostScore,
    NULL AS PostViewCount,
    NULL AS PostFavoriteCount,
    NULL AS PostAnswerCount,
    NULL AS PostCommentCount,
    NULL AS ClosedDate,
    NULL AS PostRankByOwner,
    NULL AS PreviousPostScore,
    NULL AS NextPostScore,
    NULL AS RollingAvgScore,
    NULL AS OwnerReputation,
    NULL AS OwnerCreationDate,
    NULL AS OwnerLastAccessDate,
    NULL AS OwnerUserViews,
    NULL AS OwnerUserUpVotes,
    NULL AS OwnerUserDownVotes,
    NULL AS OwnerCommentCount,
    NULL AS OwnerAvgCommentScore,
    NULL AS OwnerNegativeCommentCount,
    NULL AS OwnerPostHistoryCount,
    NULL AS OwnerBodyEdits,
    NULL AS OwnerTagEdits,
    NULL AS OwnerLastHistoryDate,
    'Summary' AS PostStatusCategory,
    NULL AS DaysSinceUserCreation,
    AVG(CAST(ScoreDifferenceFromPrevious AS FLOAT)) AS ScoreDifferenceFromPrevious,
    AVG(CAST(ScoreDifferenceToNext AS FLOAT)) AS ScoreDifferenceToNext,
    NULL AS ScoreTrend,
    'Avg Score Diff' AS ScoreLabel,
    NULL AS UserInitial,
    CONCAT('Average Rep: ', AVG(CAST(OwnerReputation AS FLOAT))) AS UserDisplayNameWithRep,
    NULL AS WebsiteStatus
FROM PostAndUserStats
WHERE PostRankByOwner <= 50
GROUP BY
    CASE WHEN PostRankByOwner <= 50 THEN 'Summary' ELSE 'Detail' END
HAVING CASE WHEN PostRankByOwner <= 50 THEN 'Summary' ELSE 'Detail' END = 'Summary';
