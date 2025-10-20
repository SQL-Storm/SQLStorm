-- {"query": "18010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1215} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as rn_score,
        AVG(CAST(p.Score AS FLOAT)) OVER (PARTITION BY p.PostTypeId) as avg_score_by_type,
        COUNT(c.Id) OVER (PARTITION BY p.Id) as comment_count_per_post
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.CreationDate >= DATE('now', '-1 year') AND p.OwnerUserId IS NOT NULL
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.Title, p.Score, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedQuestionCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= DATE('now', '-2 years')
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 5
)
SELECT
    rp.PostId,
    rp.Title,
    rp.Score,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    CASE WHEN rp.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
    CASE
        WHEN rp.rn_score <= 5 THEN 'Top 5 in Type'
        WHEN rp.Score > rp.avg_score_by_type * 1.5 THEN 'Above Average Score'
        ELSE 'Standard'
    END AS PerformanceTier,
    ups.DisplayName AS OwnerDisplayName,
    ups.Reputation AS OwnerReputation,
    ups.QuestionCount AS OwnerTotalQuestions,
    ups.AnswerCount AS OwnerTotalAnswers,
    CASE
        WHEN ups.LastPostDate < DATE('now', '-6 months') THEN 'Inactive Contributor'
        ELSE 'Active Contributor'
    END AS ContributorStatus,
    rp.comment_count_per_post,
    UPPER(SUBSTR(rp.Title, 1, 3)) || '-' || LOWER(SUBSTR(rp.Title, -3)) AS TitleSignature,
    (rp.Score + rp.AnswerCount * 5 + rp.FavoriteCount * 2) AS WeightedScore,
    (SELECT COUNT(*) FROM Comments WHERE PostId = rp.PostId AND UserId = ups.UserId) AS CommentsByUser,
    COALESCE(rp.ClosedDate, rp.LastActivityDate) AS EffectiveCloseOrActivityDate
FROM RankedPosts rp
JOIN UserPostStats ups ON rp.OwnerUserId = ups.UserId
WHERE rp.rn_score <= 10
UNION
SELECT
    rp.PostId,
    rp.Title,
    rp.Score,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    CASE WHEN rp.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
    CASE
        WHEN rp.rn_score <= 5 THEN 'Top 5 in Type'
        WHEN rp.Score > rp.avg_score_by_type * 1.5 THEN 'Above Average Score'
        ELSE 'Standard'
    END AS PerformanceTier,
    ups.DisplayName AS OwnerDisplayName,
    ups.Reputation AS OwnerReputation,
    ups.QuestionCount AS OwnerTotalQuestions,
    ups.AnswerCount AS OwnerTotalAnswers,
    CASE
        WHEN ups.LastPostDate < DATE('now', '-6 months') THEN 'Inactive Contributor'
        ELSE 'Active Contributor'
    END AS ContributorStatus,
    rp.comment_count_per_post,
    UPPER(SUBSTR(rp.Title, 1, 3)) || '-' || LOWER(SUBSTR(rp.Title, -3)) AS TitleSignature,
    (rp.Score + rp.AnswerCount * 5 + rp.FavoriteCount * 2) AS WeightedScore,
    (SELECT COUNT(*) FROM Comments WHERE PostId = rp.PostId AND UserId = ups.UserId) AS CommentsByUser,
    COALESCE(rp.ClosedDate, rp.LastActivityDate) AS EffectiveCloseOrActivityDate
FROM RankedPosts rp
JOIN UserPostStats ups ON rp.OwnerUserId = ups.UserId
WHERE rp.comment_count_per_post > 10 AND rp.PostTypeId = 1;
