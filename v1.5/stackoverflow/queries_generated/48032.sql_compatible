WITH RecentQuestions AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate AS QuestionCreationDate,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation,
        p.Score,
        p.AnswerCount,
        p.FavoriteCount,
        p.ViewCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.CreationDate > cast('2024-10-01' as date) - INTERVAL '30 days') AS RecentCommentCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2 AND v.CreationDate > cast('2024-10-01' as date) - INTERVAL '30 days') AS RecentUpVotes,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinkCount
    FROM
        Posts p
    JOIN
        Users u ON p.OwnerUserId = u.Id
    JOIN
        PostTypes pt ON p.PostTypeId = pt.Id
    WHERE
        pt.Name = 'Question'
        AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '90 days'
),
TopAnswers AS (
    SELECT
        ans.ParentId AS QuestionId,
        COUNT(ans.Id) AS NumberOfAnswers,
        SUM(ans.Score) AS TotalAnswerScore,
        AVG(ans.Score) AS AverageAnswerScore,
        MAX(ans.Score) AS MaxAnswerScore,
        COUNT(CASE WHEN ans.Id = p.AcceptedAnswerId THEN 1 END) AS IsAcceptedAnswerPresent
    FROM
        Posts ans
    JOIN
        Posts p ON ans.ParentId = p.Id
    WHERE
        ans.PostTypeId = 2 -- Answer
    GROUP BY
        ans.ParentId
)
SELECT
    rq.PostId,
    rq.Title,
    rq.QuestionCreationDate,
    rq.OwnerDisplayName,
    rq.Reputation,
    rq.Score AS QuestionScore,
    rq.AnswerCount,
    rq.FavoriteCount,
    rq.ViewCount,
    rq.RecentCommentCount,
    rq.RecentUpVotes,
    ta.NumberOfAnswers,
    ta.TotalAnswerScore,
    ta.AverageAnswerScore,
    ta.MaxAnswerScore,
    ta.IsAcceptedAnswerPresent,
    rq.DuplicateLinkCount,
    CASE
        WHEN ta.IsAcceptedAnswerPresent > 0 THEN 'Accepted Answer Exists'
        WHEN ta.NumberOfAnswers > 0 AND ta.TotalAnswerScore > 0 THEN 'Answers Exist with Score'
        WHEN ta.NumberOfAnswers > 0 THEN 'Answers Exist'
        ELSE 'No Answers'
    END AS AnswerStatus
FROM
    RecentQuestions rq
LEFT JOIN
    TopAnswers ta ON rq.PostId = ta.QuestionId
ORDER BY
    rq.Score DESC,
    rq.FavoriteCount DESC,
    rq.ViewCount DESC,
    rq.RecentUpVotes DESC
LIMIT 100;