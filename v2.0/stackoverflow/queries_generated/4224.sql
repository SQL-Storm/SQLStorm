-- {"query": "4224.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1052} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn_desc,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate ASC) AS rn_asc,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS avg_score_by_type,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS previous_post_score,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS next_post_score
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    WHERE p.Score > -5 AND p.ViewCount IS NOT NULL
),
UserPostContributions AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(p.Score) AS AvgUserPostScore
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 10
),
CommentAnalysis AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCountForPost,
        SUM(c.Score) AS TotalCommentScore,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments AS c
    WHERE c.Score > 0
    GROUP BY c.PostId
)
SELECT
    rp.PostId,
    rp.Title,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount AS PostAnswerCount,
    rp.CommentCount AS PostCommentCount,
    rp.FavoriteCount AS PostFavoriteCount,
    rp.avg_score_by_type,
    rp.previous_post_score,
    rp.next_post_score,
    upc.DisplayName AS OwnerDisplayName,
    upc.Reputation AS OwnerReputation,
    upc.QuestionCount AS OwnerQuestionCount,
    upc.AnswerCount AS OwnerAnswerCount,
    upc.TotalAnswerScore AS OwnerTotalAnswerScore,
    upc.AvgUserPostScore AS OwnerAvgPostScore,
    ca.CommentCountForPost,
    ca.TotalCommentScore,
    ca.AvgCommentScore,
    CASE WHEN rp.rn_asc <= 10 THEN 'Early' WHEN rp.rn_desc <= 10 THEN 'Late' ELSE 'Mid' END AS PostTimingGroup,
    CONCAT(
        COALESCE(upc.DisplayName, 'Anonymous'),
        ' (',
        CAST(upc.Reputation AS VARCHAR),
        ')'
    ) AS OwnerInfo,
    CASE
        WHEN rp.PostScore > rp.avg_score_by_type * 1.5 THEN 'Above Average'
        WHEN rp.PostScore < rp.avg_score_by_type * 0.5 THEN 'Below Average'
        ELSE 'Average'
    END AS ScoreRelativeToTypeAvg,
    CASE
        WHEN ca.LastCommentDate > rp.PostCreationDate + INTERVAL '1 day' THEN 'Active Comments'
        ELSE 'Inactive Comments'
    END AS CommentActivityStatus
FROM RankedPosts AS rp
LEFT JOIN UserPostContributions AS upc ON rp.OwnerUserId = upc.UserId
LEFT JOIN CommentAnalysis AS ca ON rp.PostId = ca.PostId
WHERE rp.PostTypeName IN ('Question', 'Answer')
AND upc.Reputation > 1000
ORDER BY rp.PostCreationDate DESC
LIMIT 100;
