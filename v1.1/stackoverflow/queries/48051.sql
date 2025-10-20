-- {"query": "48051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 937} 
WITH PostInteraction AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.Reputation AS OwnerReputation,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        COUNT(DISTINCT c.Id) AS CommentCount_Actual,
        COUNT(DISTINCT v.Id) AS VoteCount_Actual,
        COUNT(DISTINCT ph.Id) AS HistoryCount_Actual,
        COUNT(DISTINCT pl.Id) AS LinkCount_Actual,
        AVG(CASE WHEN c.UserId IS NOT NULL THEN u_c.Reputation ELSE 0 END) AS AvgCommenterReputation,
        MAX(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS HasUpvote,
        MAX(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS HasDownvote,
        MAX(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS HasAcceptedAnswer
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    JOIN Users AS u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    LEFT JOIN Votes AS v ON p.Id = v.PostId
    LEFT JOIN PostHistory AS ph ON p.Id = ph.PostId
    LEFT JOIN PostLinks AS pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
    LEFT JOIN Users AS u_c ON c.UserId = u_c.Id
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY
        p.Id,
        p.PostTypeId,
        pt.Name,
        p.OwnerUserId,
        u.Reputation,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate
)
SELECT
    pi.PostId,
    pi.PostTypeName,
    pi.OwnerUserId,
    pi.OwnerReputation,
    pi.PostCreationDate,
    pi.PostScore,
    pi.PostViewCount,
    pi.AnswerCount,
    pi.CommentCount,
    pi.FavoriteCount,
    pi.ClosedDate,
    pi.CommentCount_Actual,
    pi.VoteCount_Actual,
    pi.HistoryCount_Actual,
    pi.LinkCount_Actual,
    pi.AvgCommenterReputation,
    pi.HasUpvote,
    pi.HasDownvote,
    pi.HasAcceptedAnswer,
    CASE WHEN pi.PostTypeId = 1 THEN pi.PostScore * 10 + pi.AnswerCount * 5 + pi.CommentCount_Actual ELSE pi.PostScore END AS EngagementScore,
    ROW_NUMBER() OVER (PARTITION BY pi.PostTypeId ORDER BY pi.PostScore DESC, pi.PostCreationDate ASC) AS RankByScore,
    ROW_NUMBER() OVER (PARTITION BY pi.PostTypeId ORDER BY pi.PostViewCount DESC, pi.PostCreationDate ASC) AS RankByViewCount,
    ROW_NUMBER() OVER (PARTITION BY pi.PostTypeId ORDER BY pi.PostCreationDate DESC) AS RankByRecency,
    CASE
        WHEN pi.ClosedDate IS NOT NULL THEN 1
        ELSE 0
    END AS IsClosed,
    CASE
        WHEN pi.OwnerReputation > 10000 THEN 'High Reputation'
        WHEN pi.OwnerReputation > 1000 THEN 'Medium Reputation'
        ELSE 'Low Reputation'
    END AS OwnerReputationTier
FROM PostInteraction AS pi
WHERE pi.PostTypeId = 1
ORDER BY pi.PostScore DESC, pi.PostCreationDate ASC
LIMIT 1000;