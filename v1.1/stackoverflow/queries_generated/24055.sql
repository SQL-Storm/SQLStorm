-- {"query": "24055.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3773} 

WITH closed_qs AS(
    SELECT
        p.Id                                     AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        p.ClosedDate,
        COALESCE(u.Reputation,0)                AS OwnerReputation,
        COALESCE(SUM(CASE WHEN v.VoteTypeId=2 THEN 1 END),0) AS UpvoteCount
    FROM Posts p
    LEFT JOIN Users u    ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v    ON v.PostId = p.Id
    WHERE p.PostTypeId=1
      AND p.ClosedDate IS NOT NULL
      AND p.AcceptedAnswerId IS NOT NULL
    GROUP BY p.Id,p.Title,p.CreationDate,p.Tags,p.AcceptedAnswerId,p.ClosedDate,u.Reputation
),
duplicate_qs AS(
    SELECT
        sl.PostId                               AS QuestionId,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        NULL::timestamp                         AS ClosedDate,
        COALESCE(u.Reputation,0)                AS OwnerReputation,
        NULL::integer                           AS UpvoteCount
    FROM PostLinks sl
    JOIN Posts p                ON p.Id = sl.PostId
    LEFT JOIN Users u           ON u.Id = p.OwnerUserId
    WHERE sl.LinkTypeId=3        -- duplicate links
      AND p.PostTypeId=1
),
combined AS(
    SELECT * FROM closed_qs
    UNION ALL
    SELECT * FROM duplicate_qs
),
comment_stats AS(
    SELECT
        c.PostId                                     AS QuestionId,
        COUNT(*)                                     AS TotalComments,
        string_agg(DISTINCT c.UserDisplayName, ', ')   AS CommenterList
    FROM Comments c
    WHERE c.PostId IN (SELECT QuestionId FROM combined)
    GROUP BY c.PostId
),
answer_stats AS(
    SELECT
        a.ParentId                                   AS QuestionId,
        COUNT(*)                                     AS AnswerCount,
        AVG(a.Score)                                 AS AvgAnswerScore,
        COALESCE(SUM(CASE WHEN v.VoteTypeId=2 THEN 1 END),0) AS AnswerUpvotes
    FROM Posts a
    LEFT JOIN Votes v ON v.PostId = a.Id AND v.VoteTypeId=2
    WHERE a.PostTypeId=2
    GROUP BY a.ParentId
),
final AS(
    SELECT
        c.QuestionId,
        c.Title,
        c.CreationDate,
        c.Tags,
        c.AcceptedAnswerId,
        c.ClosedDate,
        c.OwnerReputation,
        COALESCE(c.UpvoteCount,0)                     AS UpvoteCount,
        cs.TotalComments,
        cs.CommenterList,
        as_ans.AnswerCount,
        as_ans.AvgAnswerScore,
        as_ans.AnswerUpvotes,
        -- correlated sub‑query for the raw up‑vote count on the post itself
        (SELECT COUNT(*) FROM Votes v2
         WHERE v2.PostId = c.QuestionId AND v2.VoteTypeId=2) AS PostUpvotes,
        -- window function ranking by answer up‑votes
        ROW_NUMBER() OVER (PARTITION BY c.QuestionId
                           ORDER BY as_ans.AnswerUpvotes DESC) AS RankByAnsUpvotes
    FROM combined c
    LEFT JOIN comment_stats cs ON cs.QuestionId = c.QuestionId
    LEFT JOIN answer_stats as_ans ON as_ans.QuestionId = c.QuestionId
)
SELECT *
FROM final
WHERE RankByAnsUpvotes = 1
ORDER BY AvgAnswerScore DESC NULLS LAST,
         PostUpvotes DESC,
         CreatedDate DESC
LIMIT 100;
