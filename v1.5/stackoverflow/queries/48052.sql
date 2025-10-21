-- {"query": "48052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 697} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 5) AS EditBodyCount,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS RowNum
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
),
TopQuestions AS (
    SELECT * FROM RankedPosts WHERE RowNum <= 100
),
AggregatedComments AS (
    SELECT
        c.PostId,
        AVG(c.Score) AS AvgCommentScore,
        COUNT(*) AS TotalComments
    FROM Comments c
    JOIN TopQuestions tq ON c.PostId = tq.PostId
    GROUP BY c.PostId
),
AggregatedPostHistory AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 ELSE NULL END) AS EditTitleCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 6 THEN 1 ELSE NULL END) AS EditTagsCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    JOIN TopQuestions tq ON ph.PostId = tq.PostId
    GROUP BY ph.PostId
)
SELECT
    tq.PostId,
    tq.Title,
    tq.PostCreationDate,
    tq.PostScore,
    tq.PostViewCount,
    tq.OwnerDisplayName,
    tq.OwnerReputation,
    COALESCE(ac.AvgCommentScore, 0) AS AverageCommentScore,
    COALESCE(ac.TotalComments, 0) AS TotalCommentsOnTopQuestion,
    COALESCE(aph.EditTitleCount, 0) AS TitleEdits,
    COALESCE(aph.EditTagsCount, 0) AS TagsEdits,
    COALESCE(tq.EditBodyCount, 0) AS BodyEdits,
    tq.PostCreationDate AS QuestionFirstSeen,
    COALESCE(aph.LastEditDate, tq.PostCreationDate) AS QuestionLastActivity
FROM TopQuestions tq
LEFT JOIN AggregatedComments ac ON tq.PostId = ac.PostId
LEFT JOIN AggregatedPostHistory aph ON tq.PostId = aph.PostId
ORDER BY tq.PostScore DESC, tq.PostViewCount DESC
LIMIT 50;