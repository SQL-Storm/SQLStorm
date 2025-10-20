-- {"query": "48036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 845} 

WITH RecentQuestions AS (
    SELECT
        Id,
        OwnerUserId,
        Title,
        CreationDate,
        Score,
        ViewCount,
        AnswerCount,
        FavoriteCount
    FROM Posts
    WHERE PostTypeId = 1 AND CreationDate >= DATE('now', '-1 year')
),
QuestionActivity AS (
    SELECT
        q.Id AS QuestionId,
        COUNT(CASE WHEN c.VoteTypeId = 2 THEN 1 END) AS Upvotes,
        COUNT(CASE WHEN c.VoteTypeId = 3 THEN 1 END) AS Downvotes,
        COUNT(DISTINCT c.UserId) AS DistinctVoters,
        SUM(CASE WHEN c.VoteTypeId = 8 THEN c.BountyAmount ELSE 0 END) AS TotalBountyAmount,
        COUNT(DISTINCT a.Id) AS NumberOfAnswers,
        COUNT(DISTINCT CASE WHEN a.AcceptedAnswerId IS NOT NULL THEN a.Id END) AS IsAcceptedAnswerPresent
    FROM RecentQuestions q
    LEFT JOIN Votes c ON q.Id = c.PostId
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    GROUP BY q.Id
),
UserReputation AS (
    SELECT
        Id,
        Reputation,
        Views,
        UpVotes AS UserUpVotes,
        DownVotes AS UserDownVotes,
        CreationDate AS UserCreationDate
    FROM Users
),
TagPopularity AS (
    SELECT
        SUBSTRING(value, 2, LENGTH(value) - 2) AS TagName,
        COUNT(*) AS TagCount
    FROM RecentQuestions
    CROSS JOIN UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(Tags, '<', ''), '>', ''), '')) AS value
    GROUP BY TagName
    ORDER BY TagCount DESC
    LIMIT 10
)
SELECT
    rq.Id AS QuestionId,
    rq.Title AS QuestionTitle,
    rq.CreationDate AS QuestionCreationDate,
    rq.Score AS QuestionScore,
    rq.ViewCount AS QuestionViewCount,
    rq.AnswerCount AS QuestionAnswerCount,
    rq.FavoriteCount AS QuestionFavoriteCount,
    qa.Upvotes AS QuestionUpvotes,
    qa.Downvotes AS QuestionDownvotes,
    qa.DistinctVoters AS QuestionDistinctVoters,
    qa.TotalBountyAmount,
    qa.NumberOfAnswers AS ActualAnswerCount,
    qa.IsAcceptedAnswerPresent,
    ur.Reputation AS OwnerReputation,
    ur.Views AS OwnerViews,
    ur.UserUpVotes AS OwnerTotalUpvotes,
    ur.UserDownVotes AS OwnerTotalDownvotes,
    tp.TagName AS TopTag,
    tp.TagCount AS TopTagCount
FROM RecentQuestions rq
JOIN QuestionActivity qa ON rq.Id = qa.QuestionId
JOIN UserReputation ur ON rq.OwnerUserId = ur.Id
LEFT JOIN (
    SELECT
        rq_inner.Id,
        tp_inner.TagName,
        tp_inner.TagCount,
        ROW_NUMBER() OVER(PARTITION BY rq_inner.Id ORDER BY tp_inner.TagCount DESC) as rn
    FROM RecentQuestions rq_inner
    CROSS JOIN UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(rq_inner.Tags, '<', ''), '>', ''), '')) AS tag_value
    JOIN TagPopularity tp_inner ON SUBSTRING(tag_value, 2, LENGTH(tag_value) - 2) = tp_inner.TagName
) tp ON rq.Id = tp.Id AND tp.rn = 1
ORDER BY
    rq.CreationDate DESC,
    rq.Score DESC
LIMIT 1000;
