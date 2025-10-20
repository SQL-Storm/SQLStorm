WITH
TagCandidates AS (
    SELECT t.TagName, t.Count, p2.Id AS PostId, p2.Tags
    FROM Tags t
    CROSS JOIN Posts p2
),
TagRanks AS (
    SELECT
        p.Id AS PostId,
        m.TagName,
        m.Count,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY m.Count DESC) AS TagRank
    FROM Posts p
    JOIN TagCandidates tc ON p.Id = tc.PostId
    -- emulate CROSS APPLY substring by using standard SQL function call in a derived column
    -- extract tag string without surrounding characters if applicable
    JOIN (
      SELECT tc2.PostId,
             tc2.TagName,
             tc2.Count,
             CASE
               WHEN tc2.Tags IS NULL THEN NULL
               WHEN LENGTH(tc2.Tags) >= 2 THEN SUBSTRING(tc2.Tags FROM 2 FOR (LENGTH(tc2.Tags) - 2))
               ELSE tc2.Tags
             END AS TagsStr
      FROM TagCandidates tc2
    ) m ON m.PostId = tc.PostId AND m.TagName = tc.TagName AND m.Count = tc.Count
    WHERE POSITION('<' || m.TagName || '>' IN p.Tags) > 0
      AND p.PostTypeId = 1
),
AnswerCnt AS (
    SELECT ParentId, COUNT(*) AS AnswerCount
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
),
CommentCnt AS (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
),
VoteAgg AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVotes
    FROM Votes v
    GROUP BY v.PostId
),
EditTimes AS (
    SELECT
        ph.PostId,
        MIN(ph.CreationDate) AS FirstEditDate,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,11,12,13,14,15)
    GROUP BY ph.PostId
)
SELECT
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    p.Score,
    COALESCE(a.AnswerCount, 0) AS AnswerCount,
    COALESCE(c.CommentCount, 0) AS CommentCount,
    COALESCE(v.UpVotes, 0) AS UpVotes,
    COALESCE(v.DownVotes, 0) AS DownVotes,
    COALESCE(v.AcceptedVotes, 0) AS AcceptedVotes,
    COALESCE(e.FirstEditDate, NULL) AS FirstEditDate,
    COALESCE(e.LastEditDate, NULL) AS LastEditDate,
    STRING_AGG(t.TagName, ',' ORDER BY t.Count DESC) AS TopTags
FROM Posts p
LEFT JOIN AnswerCnt a ON a.ParentId = p.Id
LEFT JOIN CommentCnt c ON c.PostId = p.Id
LEFT JOIN VoteAgg v ON v.PostId = p.Id
LEFT JOIN EditTimes e ON e.PostId = p.Id
LEFT JOIN TagRanks t ON t.PostId = p.Id AND t.TagRank <= 3
WHERE p.PostTypeId = 1
GROUP BY
    p.Id, p.Title, p.CreationDate, p.Score,
    a.AnswerCount, c.CommentCount,
    v.UpVotes, v.DownVotes, v.AcceptedVotes,
    e.FirstEditDate, e.LastEditDate
ORDER BY p.Score DESC, a.AnswerCount DESC
LIMIT 100;