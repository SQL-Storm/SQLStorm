-- {"query": "4918.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 935}
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        pht.Name AS EditType,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserEditSummary AS (
    SELECT
        rpe.UserId,
        COUNT(DISTINCT rpe.PostId) AS PostsEditedCount,
        SUM(CASE WHEN rpe.EditType = 'Edit Body' THEN 1 ELSE 0 END) AS BodyEdits,
        MAX(rpe.CreationDate) AS LatestEditDate,
        AVG(EXTRACT(EPOCH FROM (rpe.CreationDate - u.CreationDate))) AS AvgEditLagSeconds
    FROM RankedPostEdits rpe
    JOIN Users u ON rpe.UserId = u.Id
    GROUP BY rpe.UserId
    HAVING COUNT(DISTINCT rpe.PostId) > 5
),
QuestionAnswerStats AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.AnswerCount,
        p.FavoriteCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 5) AS HighScoreCommentCount,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        CAST(EXTRACT(YEAR FROM p.CreationDate) AS VARCHAR) AS QuestionYear,
        CASE WHEN UPPER(p.Tags) LIKE '%<SQL>%' THEN 1 ELSE 0 END AS IsSqlRelated
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TopAnswerers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS AnswerCount,
        SUM(p.Score) AS TotalScore
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 2
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(p.Id) > 10
)
SELECT
    qas.Title AS QuestionTitle,
    qas.QuestionYear,
    qas.IsSqlRelated,
    qas.AnswerCount,
    qas.FavoriteCount,
    qas.HighScoreCommentCount,
    qas.HasAcceptedAnswer,
    ues.UserId AS MostActiveEditorId,
    ues.PostsEditedCount,
    ues.BodyEdits,
    ues.AvgEditLagSeconds,
    ta.DisplayName AS TopAnswererName,
    ta.TotalScore AS TopAnswererScore,
    CASE
        WHEN qas.FavoriteCount > 100 THEN 'Very Popular'
        WHEN qas.FavoriteCount > 50 THEN 'Popular'
        ELSE 'Standard'
    END AS PopularityBucket,
    COALESCE(qas.AnswerCount, 0) + COALESCE(qas.FavoriteCount, 0) AS CombinedMetric
FROM QuestionAnswerStats qas
LEFT JOIN UserEditSummary ues
  ON qas.QuestionYear = CAST(EXTRACT(YEAR FROM ues.LatestEditDate) AS VARCHAR)
     AND ues.PostsEditedCount > 5
LEFT JOIN TopAnswerers ta
  ON ta.TotalScore > (SELECT AVG(TotalScore) FROM TopAnswerers)
WHERE qas.QuestionYear BETWEEN '2010' AND '2023'
  AND qas.AnswerCount >= 0
ORDER BY qas.FavoriteCount DESC, qas.AnswerCount DESC
FETCH FIRST 1000 ROWS ONLY;