-- {"query": "4144.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1653}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ViewCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS RowNum,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
),
UserActivity AS (
    SELECT
        OwnerUserId AS UserId,
        COUNT(Id) AS TotalPosts,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(CAST(Score AS NUMERIC(10, 2))) AS AverageScore,
        MAX(CreationDate) AS LastPostDate
    FROM Posts
    WHERE OwnerUserId IS NOT NULL AND OwnerUserId <> -1
    GROUP BY OwnerUserId
),
PostHistoryAnalysis AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 END) AS TitleEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) AS BodyEdits,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastCloseDate,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN 1 END) AS ModerationEvents
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 10, 11, 12, 13)
    GROUP BY ph.PostId
),
AggregatedData AS (
    SELECT
        rp.PostId,
        rp.PostTypeName,
        rp.OwnerUserId,
        rp.OwnerDisplayName,
        rp.PostCreationDate,
        rp.PostScore,
        rp.AnswerCount AS PostAnswerCount,
        rp.CommentCount AS PostCommentCount,
        rp.FavoriteCount AS PostFavoriteCount,
        rp.ViewCount AS PostViewCount,
        rp.ClosedDate,
        rp.RowNum,
        rp.ScoreRank,
        rp.PreviousPostScore,
        ua.TotalPosts AS OwnerTotalPosts,
        ua.QuestionCount AS OwnerQuestionCount,
        ua.AnswerCount AS OwnerAnswerCount,
        ua.AverageScore AS OwnerAverageScore,
        pha.TitleEdits,
        pha.BodyEdits,
        pha.LastCloseDate,
        pha.ModerationEvents,
        COALESCE(pht.Name, 'N/A') AS LastModerationAction
    FROM RankedPosts rp
    LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
    LEFT JOIN PostHistoryAnalysis pha ON rp.PostId = pha.PostId
    LEFT JOIN PostHistory ph_last_mod ON rp.PostId = ph_last_mod.PostId AND ph_last_mod.CreationDate = pha.LastCloseDate
    LEFT JOIN PostHistoryTypes pht ON ph_last_mod.PostHistoryTypeId = pht.Id
    WHERE rp.PostScore > 10 OR rp.AnswerCount > 5
)
SELECT
    ad.PostId,
    ad.PostTypeName,
    ad.OwnerDisplayName,
    ad.PostCreationDate,
    ad.PostScore,
    ad.PostAnswerCount,
    ad.PostCommentCount,
    ad.PostFavoriteCount,
    ad.PostViewCount,
    ad.ClosedDate,
    ad.RowNum,
    ad.ScoreRank,
    ad.PreviousPostScore,
    ad.OwnerTotalPosts,
    ad.OwnerQuestionCount,
    ad.OwnerAnswerCount,
    ad.OwnerAverageScore,
    ad.TitleEdits,
    ad.BodyEdits,
    ad.LastCloseDate,
    ad.ModerationEvents,
    ad.LastModerationAction,
    CASE
        WHEN ad.PostScore > 500 AND ad.OwnerTotalPosts > 1000 THEN 'High Performing Post by Expert'
        WHEN ad.PostAnswerCount > 10 AND ad.OwnerAverageScore > 20 THEN 'Popular Question with High Engagement'
        WHEN ad.BodyEdits > 5 AND ad.PostScore < 0 THEN 'Constantly Edited, Poorly Received Post'
        WHEN ad.ModerationEvents > 2 AND ad.ClosedDate IS NOT NULL THEN 'Frequently Moderated and Closed Post'
        ELSE 'Standard Post Performance'
    END AS PerformanceCategory,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ad.PostId AND c.Score < 0) AS NegativeCommentCount,
    CASE
        WHEN CHAR_LENGTH(ad.OwnerDisplayName) > 15 THEN SUBSTRING(ad.OwnerDisplayName FROM 1 FOR 15) || '...'
        ELSE ad.OwnerDisplayName
    END AS TruncatedOwnerName,
    COALESCE(u.Reputation, 0) AS OwnerReputation
FROM AggregatedData ad
LEFT JOIN Users u ON ad.OwnerUserId = u.Id
WHERE ad.PostViewCount > 1000 OR ad.PostScore > 50

UNION ALL

SELECT
    CAST(NULL AS BIGINT) AS PostId,
    'Summary' AS PostTypeName,
    'N/A' AS OwnerDisplayName,
    CAST(NULL AS TIMESTAMP) AS PostCreationDate,
    AVG(ad.PostScore) AS PostScore,
    AVG(CAST(ad.PostAnswerCount AS NUMERIC(10,2))) AS PostAnswerCount,
    AVG(CAST(ad.PostCommentCount AS NUMERIC(10,2))) AS PostCommentCount,
    AVG(CAST(ad.PostFavoriteCount AS NUMERIC(10,2))) AS PostFavoriteCount,
    AVG(CAST(ad.PostViewCount AS NUMERIC(10,2))) AS PostViewCount,
    CAST(NULL AS TIMESTAMP) AS ClosedDate,
    AVG(CAST(ad.RowNum AS NUMERIC(10,2))) AS RowNum,
    AVG(CAST(ad.ScoreRank AS NUMERIC(10,2))) AS ScoreRank,
    AVG(CAST(ad.PreviousPostScore AS NUMERIC(10,2))) AS PreviousPostScore,
    AVG(CAST(ad.OwnerTotalPosts AS NUMERIC(10,2))) AS OwnerTotalPosts,
    AVG(CAST(ad.OwnerQuestionCount AS NUMERIC(10,2))) AS OwnerQuestionCount,
    AVG(CAST(ad.OwnerAnswerCount AS NUMERIC(10,2))) AS OwnerAnswerCount,
    AVG(CAST(ad.OwnerAverageScore AS NUMERIC(10,2))) AS OwnerAverageScore,
    AVG(CAST(ad.TitleEdits AS NUMERIC(10,2))) AS TitleEdits,
    AVG(CAST(ad.BodyEdits AS NUMERIC(10,2))) AS BodyEdits,
    CAST(NULL AS TIMESTAMP) AS LastCloseDate,
    AVG(CAST(ad.ModerationEvents AS NUMERIC(10,2))) AS ModerationEvents,
    'Overall Average' AS LastModerationAction,
    '0' AS PerformanceCategory,
    0 AS NegativeCommentCount,
    'N/A' AS TruncatedOwnerName,
    AVG(CAST(COALESCE(u.Reputation, 0) AS NUMERIC(10,2))) AS OwnerReputation
FROM AggregatedData ad
LEFT JOIN Users u ON ad.OwnerUserId = u.Id;