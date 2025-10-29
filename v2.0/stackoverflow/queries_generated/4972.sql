-- {"query": "4972.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 990} 

WITH PostEditSummary AS (
    SELECT
        ph.PostId,
        ph.UserId,
        u.DisplayName AS EditorDisplayName,
        ph.CreationDate AS EditDate,
        ph.Comment AS EditComment,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
LatestPostEdits AS (
    SELECT * FROM PostEditSummary WHERE rn = 1
),
AnswerVoteStats AS (
    SELECT
        p.Id AS AnswerId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE NULL END) AS UpVoteCount,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE NULL END) AS DownVoteCount,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) - SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS NetVoteScore
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE p.PostTypeId = 2 -- Answer
    GROUP BY p.Id
),
UserAnswerQuality AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
        AVG(COALESCE(avs.NetVoteScore, 0)) AS AverageAnswerNetScore,
        SUM(CASE WHEN p.PostTypeId = 2 AND avs.UpVoteCount > 10 THEN 1 ELSE 0 END) AS HighQualityAnswerCount,
        MAX(p.CreationDate) AS LastAnswerDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN AnswerVoteStats avs ON p.Id = avs.AnswerId
    WHERE p.PostTypeId = 2 -- Answer
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) > 5
)
SELECT
    q.Id AS QuestionId,
    q.Title AS QuestionTitle,
    q.CreationDate AS QuestionCreationDate,
    q.OwnerUserId AS QuestionOwnerUserId,
    qo.DisplayName AS QuestionOwnerDisplayName,
    q.AnswerCount,
    q.FavoriteCount,
    q.ViewCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id AND c.Score > 5) AS HighScoringCommentCount,
    COALESCE(q.Score, 0) AS QuestionScore,
    CASE
        WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN q.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
    END AS QuestionStatus,
    uaq.DisplayName AS TopAnswererDisplayName,
    uaq.AverageAnswerNetScore,
    uaq.HighQualityAnswerCount,
    lpe.EditorDisplayName AS LastEditor,
    lpe.EditDate AS LastEditDate,
    lpe.EditComment AS LastEditComment,
    pl.RelatedPostId AS DuplicateOfPostId
FROM Posts q
LEFT JOIN Users qo ON q.OwnerUserId = qo.Id
LEFT JOIN (
    SELECT *
    FROM UserAnswerQuality
    ORDER BY HighQualityAnswerCount DESC, AverageAnswerNetScore DESC
    LIMIT 1
) AS uaq ON 1=1 -- Cross join to get the overall top answerer for each question
LEFT JOIN LatestPostEdits lpe ON q.Id = lpe.PostId
LEFT JOIN PostLinks pl ON q.Id = pl.PostId AND pl.LinkTypeId = 3 -- 3 = Duplicate
WHERE q.PostTypeId = 1 -- Question
AND q.CreationDate >= DATE('now', '-1 year')
AND q.ViewCount > 1000
AND EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = q.Id AND c.Text LIKE '%performance%')
ORDER BY q.LastActivityDate DESC
LIMIT 50;
