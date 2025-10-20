WITH QuestionStats AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate AS QuestionCreationDate,
        u.DisplayName AS OwnerDisplayName,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id) AS LinkCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5) AS FavoriteVoteCount
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        SUM(a.Score) AS TotalAnswerScore,
        AVG(a.Score) AS AverageAnswerScore,
        COUNT(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId = a.Id THEN 1 END) AS IsAcceptedAnswer
    FROM Posts a
    LEFT JOIN Posts p ON a.ParentId = p.Id AND a.Id = p.AcceptedAnswerId
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
PostTagPairs AS (
    SELECT
        p.Id AS QuestionId,
        TRIM(tag) AS TagName
    FROM Posts p,
    LATERAL (
        SELECT regexp_split_to_table(
            regexp_replace(p.Tags, '^<|>$', '', 'g'),
            '\s+'
        ) AS tag
    ) s
    WHERE p.PostTypeId = 1
),
TagEngagement AS (
    SELECT
        pt.QuestionId,
        pt.TagName,
        COUNT(pt.TagName) OVER (PARTITION BY pt.TagName) AS TagTotalQuestions,
        SUM(p.Score) OVER (PARTITION BY pt.TagName) AS TagTotalScore,
        AVG(p.Score) OVER (PARTITION BY pt.TagName) AS TagAverageScore
    FROM Posts p
    JOIN PostTagPairs pt ON p.Id = pt.QuestionId
    /* If there's a Tags table with canonical tag names, join can be added:
       JOIN Tags t ON pt.TagName = t.TagName
       For portability, using pt.TagName directly.
    */
    WHERE p.PostTypeId = 1
)
SELECT
    qs.QuestionId,
    qs.Title,
    qs.QuestionCreationDate,
    qs.OwnerDisplayName,
    qs.QuestionScore,
    qs.QuestionViewCount,
    qs.AnswerCount,
    qs.FavoriteCount,
    qs.ClosedDate,
    qs.CommentCount,
    qs.EditCount,
    qs.LinkCount,
    qs.UpVoteCount,
    qs.DownVoteCount,
    qs.FavoriteVoteCount,
    COALESCE(ans.AnswerCount, 0) AS ActualAnswerCount,
    COALESCE(ans.TotalAnswerScore, 0) AS TotalAnswerScore,
    COALESCE(ans.AverageAnswerScore, 0) AS AverageAnswerScore,
    COALESCE(ans.IsAcceptedAnswer, 0) AS HasAcceptedAnswer,
    COUNT(te.TagName) OVER (PARTITION BY qs.QuestionId) AS UniqueTagCount,
    STRING_AGG(te.TagName, ', ' ORDER BY te.TagName) AS Tags,
    MAX(te.TagTotalQuestions) OVER (PARTITION BY qs.QuestionId) AS MaxTagQuestionCount,
    AVG(te.TagTotalScore) OVER (PARTITION BY qs.QuestionId) AS AvgTagScore,
    AVG(te.TagAverageScore) OVER (PARTITION BY qs.QuestionId) AS AvgTagAverageScore
FROM QuestionStats qs
LEFT JOIN AnswerStats ans ON qs.QuestionId = ans.QuestionId
LEFT JOIN TagEngagement te ON qs.QuestionId = te.QuestionId
WHERE qs.QuestionCreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
GROUP BY
    qs.QuestionId,
    qs.Title,
    qs.QuestionCreationDate,
    qs.OwnerDisplayName,
    qs.QuestionScore,
    qs.QuestionViewCount,
    qs.AnswerCount,
    qs.FavoriteCount,
    qs.ClosedDate,
    qs.CommentCount,
    qs.EditCount,
    qs.LinkCount,
    qs.UpVoteCount,
    qs.DownVoteCount,
    qs.FavoriteVoteCount,
    ans.AnswerCount,
    ans.TotalAnswerScore,
    ans.AverageAnswerScore,
    ans.IsAcceptedAnswer,
    te.QuestionId,
    te.TagName,
    te.TagTotalQuestions,
    te.TagTotalScore,
    te.TagAverageScore
ORDER BY qs.QuestionScore DESC, qs.QuestionViewCount DESC
LIMIT 1000;