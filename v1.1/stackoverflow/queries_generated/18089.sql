-- {"query": "18089.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1692} 

WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        u.Reputation,
        u.DisplayName AS OwnerDisplayName,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) as PostSequenceByType
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
),
PostWithRelatedData AS (
    SELECT
        rp.Id AS PostId,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.CreationDate AS PostCreationDate,
        rp.Score AS PostScore,
        rp.ViewCount AS PostViewCount,
        rp.AnswerCount AS PostAnswerCount,
        rp.CommentCount AS PostCommentCount,
        rp.FavoriteCount AS PostFavoriteCount,
        rp.ClosedDate AS PostClosedDate,
        rp.Reputation AS OwnerReputation,
        rp.OwnerDisplayName AS PostOwnerDisplayName,
        rp.ScoreRank,
        rp.PostSequenceByType,
        SUM(CASE WHEN c.UserId IS NOT NULL THEN 1 ELSE 0 END) AS CommentCountTotal,
        MAX(c.CreationDate) AS LastCommentDate,
        AVG(v.VoteTypeId) AS AverageVoteType,
        COUNT(DISTINCT v.UserId) AS DistinctVoters
    FROM RankedPosts rp
    LEFT JOIN Comments c ON rp.Id = c.PostId
    LEFT JOIN Votes v ON rp.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    GROUP BY
        rp.Id,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.ClosedDate,
        rp.Reputation,
        rp.OwnerDisplayName,
        rp.ScoreRank,
        rp.PostSequenceByType
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate > DATE('2023-01-01')
    GROUP BY u.Id
)
SELECT
    pwr.PostId,
    pwr.PostTypeId,
    pt.Name AS PostTypeName,
    pwr.PostOwnerDisplayName,
    CASE
        WHEN pwr.OwnerReputation > 100000 THEN 'High'
        WHEN pwr.OwnerReputation > 10000 THEN 'Medium'
        ELSE 'Low'
    END AS ReputationLevel,
    pwr.PostCreationDate,
    pwr.PostScore,
    pwr.PostViewCount,
    pwr.PostAnswerCount,
    pwr.PostCommentCount,
    pwr.PostFavoriteCount,
    pwr.PostClosedDate,
    pwr.CommentCountTotal,
    pwr.LastCommentDate,
    pwr.AverageVoteType,
    pwr.DistinctVoters,
    pwr.ScoreRank,
    pwr.PostSequenceByType,
    uas.TotalPosts AS OwnerTotalPosts,
    uas.QuestionCount AS OwnerQuestionCount,
    uas.AnswerCount AS OwnerAnswerCount,
    uas.AvgPostScore AS OwnerAvgPostScore,
    uas.LastPostDate AS OwnerLastPostDate,
    uas.BadgeCount AS OwnerBadgeCount,
    COALESCE(pwr.PostScore * 1.5 + pwr.PostViewCount * 0.2, 0) AS CalculatedMetric,
    IIF(pwr.PostClosedDate IS NOT NULL, 'Closed', 'Open') AS PostStatus,
    UPPER(SUBSTRING(pwr.PostOwnerDisplayName FROM 1 FOR 3)) AS OwnerDisplayNameInitials,
    CAST(pwr.PostCreationDate AS DATE) AS PostCreationDateOnly
FROM PostWithRelatedData pwr
JOIN PostTypes pt ON pwr.PostTypeId = pt.Id
LEFT JOIN UserActivitySummary uas ON pwr.OwnerUserId = uas.UserId
WHERE pwr.PostScore > 50
UNION ALL
SELECT
    ph.PostId,
    p.PostTypeId,
    pt.Name AS PostTypeName,
    ph.UserDisplayName AS PostOwnerDisplayName,
    CASE
        WHEN u.Reputation > 100000 THEN 'High'
        WHEN u.Reputation > 10000 THEN 'Medium'
        ELSE 'Low'
    END AS ReputationLevel,
    ph.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    p.AnswerCount AS PostAnswerCount,
    p.CommentCount AS PostCommentCount,
    p.FavoriteCount AS PostFavoriteCount,
    p.ClosedDate AS PostClosedDate,
    CAST(NULL AS INT) AS CommentCountTotal,
    CAST(NULL AS TIMESTAMP) AS LastCommentDate,
    CAST(NULL AS DOUBLE PRECISION) AS AverageVoteType,
    CAST(NULL AS INT) AS DistinctVoters,
    CAST(NULL AS BIGINT) AS ScoreRank,
    CAST(NULL AS BIGINT) AS PostSequenceByType,
    uas.TotalPosts AS OwnerTotalPosts,
    uas.QuestionCount AS OwnerQuestionCount,
    uas.AnswerCount AS OwnerAnswerCount,
    uas.AvgPostScore AS OwnerAvgPostScore,
    uas.LastPostDate AS OwnerLastPostDate,
    uas.BadgeCount AS OwnerBadgeCount,
    COALESCE(p.Score * 1.5 + p.ViewCount * 0.2, 0) AS CalculatedMetric,
    'History Event' AS PostStatus,
    UPPER(SUBSTRING(ph.UserDisplayName FROM 1 FOR 3)) AS OwnerDisplayNameInitials,
    CAST(ph.CreationDate AS DATE) AS PostCreationDateOnly
FROM PostHistory ph
JOIN Posts p ON ph.PostId = p.Id
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON ph.UserId = u.Id
LEFT JOIN UserActivitySummary uas ON ph.UserId = uas.UserId
WHERE ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId IS NOT NULL AND ph.CreationDate > DATE('2023-01-01')
ORDER BY PostCreationDate DESC
LIMIT 1000;
