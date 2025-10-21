WITH QuestionTags AS (
    SELECT Id AS QuestionId,
           unnest(string_to_array(substring(Tags FROM 2 FOR length(Tags) - 2), '<>')) AS TagName
    FROM Posts
    WHERE PostTypeId = 1 AND Tags IS NOT NULL
),
Answerers AS (
    SELECT qt.QuestionId,
           qt.TagName,
           a.Id AS AnswerId,
           a.OwnerUserId,
           u.Reputation,
           a.Score
    FROM QuestionTags qt
    JOIN Posts q ON q.Id = qt.QuestionId
    JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL
    JOIN Users u ON u.Id = a.OwnerUserId
    JOIN Votes v ON v.PostId = a.Id AND v.VoteTypeId IN (2, 3)
),
TagStats AS (
    SELECT TagName,
           AVG(Reputation) AS avg_reputation,
           COUNT(DISTINCT AnswerId) AS answer_count,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS total_upvotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS total_downvotes,
           AVG(Score) AS avg_score
    FROM Answerers a
    LEFT JOIN Votes v ON v.PostId = a.AnswerId
    WHERE v.VoteTypeId IN (2, 3)
    GROUP BY TagName
),
RankedTags AS (
    SELECT TagName,
           avg_reputation,
           answer_count,
           total_upvotes,
           total_downvotes,
           avg_score,
           ROW_NUMBER() OVER (ORDER BY answer_count DESC) AS rank_by_answers,
           RANK() OVER (ORDER BY avg_reputation DESC) AS rank_by_reputation
    FROM TagStats
    WHERE answer_count > 50
)
SELECT rt.TagName,
       rt.avg_reputation,
       rt.answer_count,
       (rt.total_upvotes - rt.total_downvotes) AS net_votes,
       rt.avg_score,
       rt.rank_by_answers,
       rt.rank_by_reputation
FROM RankedTags rt
ORDER BY (rt.answer_count + (rt.total_upvotes - rt.total_downvotes) + rt.avg_reputation) DESC
LIMIT 100;