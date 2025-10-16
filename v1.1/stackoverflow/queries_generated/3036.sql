-- {"query": "3036.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1150} 
WITH QuestionStats AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Tags,
        p.ViewCount,
        p.AnswerCount,
        p.Score AS QuestionScore,
        c.CommentCount AS QuestionComments,
        v.VoteCount,
        u.Reputation,
        u.DisplayName,
        tg.TagList,
        -- Calculate days between question creation and first answer
        FIRST_VALUE(a.CreationDate) OVER (PARTITION BY p.Id ORDER BY a.CreationDate) AS FirstAnswerDate
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        (SELECT PostId, COUNT(*) AS CommentCount FROM Comments GROUP BY PostId) c ON p.Id = c.PostId
    LEFT JOIN
        (SELECT PostId, COUNT(*) AS VoteCount FROM Votes WHERE VoteTypeId = 2 GROUP BY PostId) v ON p.Id = v.PostId
    LEFT JOIN
        -- Extract tags into array for easier manipulation
        (SELECT Id, string_to_array(Tags, '><') AS TagList FROM Posts WHERE PostTypeId = 1) t ON p.Id = t.Id
    LEFT JOIN
        -- Group answers with the same question into a CTE
        (SELECT ParentId, COUNT(*) AS AnswerCount, MIN(CreationDate) AS FirstAnswerTime
         FROM Posts WHERE PostTypeId = 2 GROUP BY ParentId) a ON p.Id = a.ParentId
),
AnswerStats AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.CreationDate AS AnswerDate,
        a.Score AS AnswerScore,
        u.Reputation AS ResponderReputation,
        u.DisplayName AS ResponderName,
        votes.VoteCount AS AnswerUpvotes,
        CASE WHEN c.CommentCount IS NULL THEN 0 ELSE c.CommentCount END AS AnswerComments,
        a.Body
    FROM
        Posts a
    LEFT JOIN
        Users u ON a.OwnerUserId = u.Id
    LEFT JOIN
        (SELECT PostId, COUNT(*) AS VoteCount FROM Votes WHERE VoteTypeId = 2 GROUP BY PostId) votes ON a.Id = votes.PostId
    LEFT JOIN
        (SELECT PostId, COUNT(*) AS CommentCount FROM Comments GROUP BY PostId) c ON a.Id = c.PostId
),
CloseQuestions AS (
    SELECT
        p.Id AS QuestionId,
        r.Name AS CloseReason,
        ph.CreationDate AS CloseDate,
        ph.Comment AS CloseComment
    FROM
        Posts p
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
    LEFT JOIN
        CloseReasonTypes r ON CAST(ph.Comment AS smallint) = r.Id
),
TagUsage AS (
    SELECT
        t.TagName,
        COUNT(*) AS Occurrences,
        MAX(p.CreationDate) AS LastUsed,
        MIN(p.CreationDate) AS FirstUsed
    FROM
        Tags t
    LEFT JOIN
        Posts p ON t.ExcerptPostId = p.Id OR t.WikiPostId = p.Id
    GROUP BY
        t.TagName
),
AggregatedData AS (
    SELECT
        qs.QuestionId,
        qs.Title,
        qs.CreationDate,
        qs.Tags,
        qs.ViewCount,
        qs.AnswerCount,
        qs.QuestionScore,
        qs.QuestionComments,
        qs.VoteCount,
        qs.Reputation,
        qs.DisplayName AS AskerName,
        a.AnswerId,
        a.AnswerDate,
        a.AnswerScore,
        a.ResponderReputation,
        a.ResponderName,
        a.AnswerUpvotes,
        a.AnswerComments,
        cq.CloseReason,
        cq.CloseDate,
        cq.CloseComment,
        array_length(string_to_array(qs.Tags, '><'), 1) AS TagCount,
        COUNT(a.AnswerId) OVER (PARTITION BY qs.QuestionId) AS TotalAnswers,
        COUNT(*) OVER () AS TotalQuestions,
        ROW_NUMBER() OVER (PARTITION BY qs.QuestionId ORDER BY a.AnswerDate ASC NULLS LAST) AS FirstAnswerRank
    FROM
        QuestionStats qs
    LEFT JOIN
        AnswerStats a ON qs.QuestionId = a.QuestionId
    LEFT JOIN
        CloseQuestions cq ON qs.QuestionId = cq.QuestionId
)
SELECT
    ad.QuestionId,
    ad.Title,
    ad.CreationDate,
    ad.ViewCount,
    ad.AnswerCount,
    ad.QuestionScore,
    ad.QuestionComments,
    ad.VoteCount,
    ad.Reputation AS AskReputation,
    ad.AskerName,
    ad.AnswerId,
    ad.AnswerDate,
    ad.AnswerScore,
    ad.ResponderReputation,
    ad.ResponderName,
    ad.AnswerUpvotes,
    ad.AnswerComments,
    ad.CloseReason,
    ad.CloseDate,
    ad.CloseComment,
    ad.TagCount AS NumberOfTags,
    ad.TotalAnswers,
    ad.TotalQuestions,
    CASE WHEN ad.FirstAnswerRank = 1 THEN TRUE ELSE FALSE END AS IsFirstAnswer
FROM
    AggregatedData ad
WHERE
    (ad.AnswerId IS NULL OR ad.AnswerDate <= NOW() - INTERVAL '30 days') -- filter for recent questions or unanswered ones
ORDER BY
    ad.CreationDate DESC
LIMIT 1000;