-- {"query": "4414.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1428}
WITH PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        u.Reputation AS OwnerReputation,
        u.CreationDate AS OwnerCreationDate,
        COALESCE(SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END), 0) AS CommentCountForPost,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVoteCount,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC, p.Score DESC) AS PostRank
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
    GROUP BY
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        u.Reputation,
        u.CreationDate
),
TopPosters AS (
    SELECT
        OwnerUserId,
        SUM(PostScore) AS TotalScoreFromPosts,
        COUNT(DISTINCT PostId) AS NumPosts,
        AVG(PostRank) AS AveragePostRank
    FROM PostEngagement
    WHERE PostRank <= 1000
    GROUP BY OwnerUserId
    HAVING COUNT(DISTINCT PostId) >= 5
),
PostHistoryAnalysis AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.CreationDate ELSE NULL END) AS LastTitleEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (5, 8) THEN ph.CreationDate ELSE NULL END) AS LastBodyEditDate,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id ELSE NULL END) AS CloseVoteCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 16 THEN ph.Id ELSE NULL END) AS CommunityOwnedCount
    FROM PostHistory ph
    WHERE ph.PostId IN (SELECT PostId FROM PostEngagement)
    GROUP BY ph.PostId
),
CombinedData AS (
    SELECT
        pe.PostId,
        pe.OwnerUserId,
        pe.PostTypeId,
        pe.PostCreationDate,
        pe.PostScore,
        pe.AnswerCount,
        pe.CommentCount,
        pe.FavoriteCount,
        pe.ClosedDate,
        pe.OwnerReputation,
        pe.OwnerCreationDate,
        pe.CommentCountForPost,
        pe.UpVoteCount,
        pe.DownVoteCount,
        pe.PostRank,
        tp.TotalScoreFromPosts,
        tp.NumPosts AS PosterNumPosts,
        tp.AveragePostRank AS PosterAveragePostRank,
        pha.LastTitleEditDate,
        pha.LastBodyEditDate,
        pha.CloseVoteCount,
        pha.CommunityOwnedCount,
        CASE
            WHEN pe.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN pe.FavoriteCount > 100 AND pe.PostScore > 50 THEN 'Popular'
            WHEN pe.OwnerReputation > 10000 AND pe.PostCreationDate < (cast('2024-10-01' as date) - INTERVAL '365 day') THEN 'EstablishedUserPost'
            ELSE 'Standard'
        END AS PostCategory,
        DENSE_RANK() OVER (PARTITION BY pe.PostTypeId ORDER BY pe.PostScore DESC) AS ScoreRankForPostType,
        LAG(pe.PostScore, 1, 0) OVER (ORDER BY pe.PostCreationDate) AS PreviousPostScore,
        LEAD(pe.PostScore, 1, 0) OVER (ORDER BY pe.PostCreationDate) AS NextPostScore
    FROM PostEngagement pe
    LEFT JOIN TopPosters tp ON pe.OwnerUserId = tp.OwnerUserId
    LEFT JOIN PostHistoryAnalysis pha ON pe.PostId = pha.PostId
)
SELECT
    cd.PostId,
    pt.Name AS PostTypeName,
    cd.OwnerUserId,
    cd.OwnerReputation,
    cd.OwnerCreationDate,
    cd.PostCreationDate,
    cd.PostScore,
    cd.PostRank,
    cd.ScoreRankForPostType,
    cd.PreviousPostScore,
    cd.NextPostScore,
    cd.AnswerCount,
    cd.CommentCount,
    cd.CommentCountForPost,
    cd.FavoriteCount,
    cd.UpVoteCount,
    cd.DownVoteCount,
    cd.ClosedDate,
    cd.PostCategory,
    cd.TotalScoreFromPosts,
    cd.PosterNumPosts,
    cd.PosterAveragePostRank,
    cd.LastTitleEditDate,
    cd.LastBodyEditDate,
    cd.CloseVoteCount,
    cd.CommunityOwnedCount,
    (cd.PostScore + COALESCE(cd.FavoriteCount, 0) * 2 - COALESCE(cd.DownVoteCount, 0)) *
        CASE WHEN cd.OwnerReputation > 50000 THEN 1.5 ELSE 1 END AS EngagementScore,
    UPPER(SUBSTR(COALESCE(u.DisplayName, 'Anonymous'), 1, 1)) || LOWER(SUBSTR(COALESCE(u.DisplayName, 'Anonymous'), 2)) AS FormattedDisplayName,
    CASE
        WHEN cd.PostScore BETWEEN 0 AND 10 THEN 'Low'
        WHEN cd.PostScore BETWEEN 11 AND 50 THEN 'Medium'
        WHEN cd.PostScore > 50 THEN 'High'
        ELSE 'Very Low'
    END AS ScoreBand,
    CASE WHEN cd.ClosedDate IS NULL THEN 'Open' ELSE 'Closed' END AS PostStatus
FROM CombinedData cd
LEFT JOIN PostTypes pt ON cd.PostTypeId = pt.Id
LEFT JOIN Users u ON cd.OwnerUserId = u.Id
WHERE cd.PostRank <= 500
ORDER BY cd.PostRank;