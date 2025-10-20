WITH RecentQuestions AS (
    SELECT
        Id,
        OwnerUserId,
        Title,
        CreationDate,
        Score,
        ViewCount,
        AnswerCount,
        FavoriteCount,
        Tags
    FROM Posts
    WHERE PostTypeId = 1
      AND CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1 year')
),
QuestionActivity AS (
    SELECT
        q.Id AS QuestionId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS Upvotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS Downvotes,
        COUNT(DISTINCT v.UserId) AS DistinctVoters,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END), 0) AS TotalBountyAmount,
        COUNT(DISTINCT a.Id) AS NumberOfAnswers,
        COUNT(DISTINCT CASE WHEN a.AcceptedAnswerId IS NOT NULL THEN a.Id END) AS IsAcceptedAnswerPresent
    FROM RecentQuestions q
    LEFT JOIN Votes v ON q.Id = v.PostId
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
        TRIM(BOTH ' ' FROM SUBSTRING(tag_value FROM 2 FOR LENGTH(tag_value) - 2)) AS TagName,
        COUNT(*) AS TagCount
    FROM RecentQuestions
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(
            regexp_replace(Tags, '^<|>$', '', 'g'),
            '><'
        )) AS tag_value
    ) t
    GROUP BY TRIM(BOTH ' ' FROM SUBSTRING(tag_value FROM 2 FOR LENGTH(tag_value) - 2))
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
        rq_inner.Id AS Id,
        tp_inner.TagName AS TagName,
        tp_inner.TagCount AS TagCount,
        ROW_NUMBER() OVER(PARTITION BY rq_inner.Id ORDER BY tp_inner.TagCount DESC) AS rn
    FROM RecentQuestions rq_inner
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(
            regexp_replace(rq_inner.Tags, '^<|>$', '', 'g'),
            '><'
        )) AS tag_value
    ) t2
    JOIN TagPopularity tp_inner
      ON TRIM(BOTH ' ' FROM SUBSTRING(t2.tag_value FROM 2 FOR LENGTH(t2.tag_value) - 2)) = tp_inner.TagName
    GROUP BY rq_inner.Id, tp_inner.TagName, tp_inner.TagCount
) tp ON rq.Id = tp.Id AND tp.rn = 1
ORDER BY
    rq.CreationDate DESC,
    rq.Score DESC
LIMIT 1000;