-- {"query": "18066.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1328} 

WITH PostDetails AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ViewCount,
        p.ClosedDate,
        COALESCE(p.Tags, 'NoTags') AS Tags,
        CASE
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS QuestionOrAnswer,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.CreationDate DESC) AS RowNumScore,
        AVG(CAST(p.Score AS REAL)) OVER (PARTITION BY p.PostTypeId) AS AvgScoreForPostType,
        SUM(p.ViewCount) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningViewCount
    FROM
        Posts p
    JOIN
        PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    WHERE
        p.CreationDate >= '2023-01-01' AND p.CreationDate < '2024-01-01'
),
CommentActivity AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCountForPost,
        SUM(c.Score) AS TotalCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM
        Comments c
    GROUP BY
        c.PostId
),
VoteSummary AS (
    SELECT
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS Favorites
    FROM
        Votes v
    WHERE
        v.VoteTypeId IN (2, 3, 5)
    GROUP BY
        v.PostId
),
PostWithActivity AS (
    SELECT
        pd.*,
        COALESCE(ca.CommentCountForPost, 0) AS ActualCommentCount,
        COALESCE(ca.TotalCommentScore, 0) AS TotalCommentScore,
        ca.LastCommentDate,
        COALESCE(vs.UpVotes, 0) AS PostUpVotes,
        COALESCE(vs.DownVotes, 0) AS PostDownVotes,
        COALESCE(vs.Favorites, 0) AS PostFavorites
    FROM
        PostDetails pd
    LEFT JOIN
        CommentActivity ca ON pd.PostId = ca.PostId
    LEFT JOIN
        VoteSummary vs ON pd.PostId = vs.PostId
),
UserReputationRank AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM
        Users u
)
SELECT
    pwa.PostId,
    pwa.PostTypeName,
    pwa.OwnerDisplayName,
    pwa.CreationDate,
    pwa.Score,
    pwa.AnswerCount,
    pwa.CommentCount,
    pwa.FavoriteCount,
    pwa.ViewCount,
    pwa.ClosedDate,
    pwa.Tags,
    pwa.QuestionOrAnswer,
    pwa.AvgScoreForPostType,
    pwa.RunningViewCount,
    pwa.ActualCommentCount,
    pwa.TotalCommentScore,
    pwa.LastCommentDate,
    pwa.PostUpVotes,
    pwa.PostDownVotes,
    pwa.PostFavorites,
    CASE
        WHEN pwa.Score > pwa.AvgScoreForPostType * 1.5 THEN 'Above Average Score'
        WHEN pwa.Score < pwa.AvgScoreForPostType * 0.5 THEN 'Below Average Score'
        ELSE 'Average Score'
    END AS ScoreCategory,
    CASE
        WHEN pwa.LastCommentDate IS NULL THEN 'No Comments'
        WHEN pwa.LastCommentDate > DATE_SUB(pwa.CreationDate, INTERVAL 1 HOUR) THEN 'High Comment Activity'
        ELSE 'Low Comment Activity'
    END AS CommentActivityLevel,
    CASE
        WHEN pwa.PostUpVotes > pwa.PostDownVotes * 2 THEN 'Positive Sentiment'
        WHEN pwa.PostDownVotes > pwa.PostUpVotes * 2 THEN 'Negative Sentiment'
        ELSE 'Neutral Sentiment'
    END AS VoteSentiment,
    CASE
        WHEN pwa.OwnerUserId IS NOT NULL THEN urr.ReputationRank
        ELSE NULL
    END AS OwnerReputationRank,
    'PostScore' || CAST(pwa.Score AS VARCHAR(10)) || '-' || pwa.PostTypeName AS CompositeIdentifier
FROM
    PostWithActivity pwa
LEFT JOIN
    UserReputationRank urr ON pwa.OwnerUserId = urr.UserId
WHERE
    pwa.Score > 10
    AND pwa.AnswerCount < 5
    AND pwa.ViewCount > 1000
    AND pwa.ClosedDate IS NULL
    AND pwa.Tags LIKE '%sql%'
    AND (pwa.OwnerDisplayName IS NOT NULL OR pwa.OwnerUserId IS NULL)
ORDER BY
    pwa.Score DESC, pwa.CreationDate DESC
LIMIT 100;
