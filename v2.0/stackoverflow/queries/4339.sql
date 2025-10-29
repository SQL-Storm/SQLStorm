-- {"query": "4339.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 939}
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserEdits AS (
    SELECT
        rpe.PostId,
        rpe.UserId,
        u.DisplayName AS EditorDisplayName,
        p.Title AS PostTitle,
        p.PostTypeId,
        rpe.CreationDate AS LastEditDate,
        CASE
            WHEN rpe.PostHistoryTypeId = 4 THEN 'Title'
            WHEN rpe.PostHistoryTypeId = 5 THEN 'Body'
            WHEN rpe.PostHistoryTypeId = 6 THEN 'Tags'
            ELSE 'Unknown'
        END AS EditType,
        LEAD(rpe.CreationDate, 1) OVER(PARTITION BY rpe.PostId, rpe.UserId ORDER BY rpe.CreationDate ASC) AS NextEditDate,
        ROW_NUMBER() OVER(PARTITION BY rpe.PostId, rpe.UserId ORDER BY rpe.CreationDate ASC) AS edit_seq_num
    FROM RankedPostEdits rpe
    JOIN Users u ON rpe.UserId = u.Id
    JOIN Posts p ON rpe.PostId = p.Id
    WHERE rpe.rn = 1
),
PostEditDurations AS (
    SELECT
        ue.PostId,
        ue.UserId,
        ue.EditorDisplayName,
        ue.PostTitle,
        ue.PostTypeId,
        ue.LastEditDate,
        ue.EditType,
        ue.NextEditDate,
        ue.edit_seq_num,
        -- compute difference in minutes between two timestamps in a portable way: seconds/60
        EXTRACT(EPOCH FROM (ue.NextEditDate - ue.LastEditDate)) / 60.0 AS TimeToNextEditMinutes
    FROM UserEdits ue
),
AggregatedEditDurations AS (
    SELECT
        PostId,
        PostTitle,
        PostTypeId,
        UserId,
        EditorDisplayName,
        AVG(CAST(TimeToNextEditMinutes AS DOUBLE PRECISION)) AS AvgTimeToNextEditMinutes,
        COUNT(DISTINCT edit_seq_num) AS NumberOfEdits
    FROM PostEditDurations
    WHERE TimeToNextEditMinutes IS NOT NULL
    GROUP BY PostId, PostTitle, PostTypeId, UserId, EditorDisplayName
    HAVING COUNT(DISTINCT edit_seq_num) > 1
),
TopEditors AS (
    SELECT
        UserId,
        EditorDisplayName,
        COUNT(DISTINCT PostId) AS DistinctPostsEdited,
        SUM(NumberOfEdits) AS TotalEdits,
        AVG(AvgTimeToNextEditMinutes) AS AvgTimeToNextEditAcrossPosts
    FROM AggregatedEditDurations
    GROUP BY UserId, EditorDisplayName
    ORDER BY TotalEdits DESC
    LIMIT 10
)
SELECT
    te.UserId,
    te.EditorDisplayName,
    te.DistinctPostsEdited,
    te.TotalEdits,
    ROUND(CAST(te.AvgTimeToNextEditAcrossPosts AS NUMERIC), 2) AS AvgTimeToNextEdit,
    COALESCE(MAX(p.AnswerCount), 0) AS MaxAnswerCountForEditedPosts,
    SUM(CASE WHEN p.Score > 100 THEN 1 ELSE 0 END) AS HighScorePostsEdited,
    COUNT(DISTINCT ae.PostId) AS CountOfPostsWithMultipleEdits,
    SUM(CASE WHEN pt.Name IS NULL THEN 1 ELSE 0 END) AS PostsWithUnknownPostType
FROM TopEditors te
LEFT JOIN AggregatedEditDurations ae ON te.UserId = ae.UserId
LEFT JOIN Posts p ON ae.PostId = p.Id
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
GROUP BY te.UserId, te.EditorDisplayName, te.DistinctPostsEdited, te.TotalEdits, te.AvgTimeToNextEditAcrossPosts
HAVING COUNT(DISTINCT ae.PostId) > 1 OR te.TotalEdits > 5
ORDER BY te.TotalEdits DESC, te.DistinctPostsEdited DESC;