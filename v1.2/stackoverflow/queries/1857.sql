WITH RecursiveTagCounts AS (
    SELECT 
        t.Id AS TagId, 
        t.TagName,
        COALESCE(tp.Score, 0) AS PostScore,
        ARRAY[tp.Id] AS PostAnswers
    FROM Tags t
    LEFT JOIN Posts tp ON tp.Tags LIKE '%' || '<' || t.TagName || '>' || '%' AND tp.PostTypeId = 1
    WHERE tp.PostTypeId = 1 AND tp.AnswerCount IS NOT NULL
),
TagAggregates AS (
    SELECT
        r.TagId,
        r.TagName,
        COUNT(*) AS QuestionCount,
        SUM(r.PostScore) AS TotalScore,
        AVG(r.PostScore) AS AvgScore
    FROM RecursiveTagCounts r
    GROUP BY r.TagId, r.TagName
),
CloseVoteDetails AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS CloseEvents,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastCloseEventDate
    FROM PostHistory ph
    GROUP BY ph.PostId
)
SELECT
    ta.TagId,
    ta.TagName,
    ta.QuestionCount,
    ta.TotalScore,
    ta.AvgScore,
    COALESCE(cvd.CloseEvents, 0) AS CloseEvents,
    cvd.LastCloseEventDate
FROM TagAggregates ta
LEFT JOIN CloseVoteDetails cvd ON cvd.PostId = ta.TagId
GROUP BY
    ta.TagId,
    ta.TagName,
    ta.QuestionCount,
    ta.TotalScore,
    ta.AvgScore,
    cvd.CloseEvents,
    cvd.LastCloseEventDate;