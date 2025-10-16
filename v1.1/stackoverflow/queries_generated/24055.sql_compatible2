WITH closed_qs AS (
    SELECT
        p.Id                                     AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        p.ClosedDate,
        COALESCE(u.Reputation, 0)                AS OwnerReputation,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpvoteCount
    FROM Posts p
    LEFT JOIN Users u    ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v    ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.ClosedDate IS NOT NULL
      AND p.AcceptedAnswerId IS NOT NULL
    GROUP BY p.Id, p.Title, p.CreationDate, p.Tags, p.AcceptedAnswerId, p.ClosedDate, u.Reputation
),
duplicate_qs AS (
    SELECT
        sl.PostId                               AS QuestionId,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        CAST(NULL AS TIMESTAMP)                 AS ClosedDate,
        COALESCE(u.Reputation, 0)               AS OwnerReputation,
        CAST(NULL AS INTEGER)                   AS UpvoteCount
    FROM PostLinks sl
    JOIN Posts p                ON p.Id = sl.PostId
    LEFT JOIN Users u           ON u.Id = p.OwnerUserId
    WHERE sl.LinkTypeId = 3        -- duplicate links
      AND p.PostTypeId = 1
),
combined AS (
    SELECT QuestionId, Title, CreationDate, Tags, AcceptedAnswerId, ClosedDate, OwnerReputation, UpvoteCount FROM closed_qs
    UNION ALL
    SELECT QuestionId, Title, NULL AS CreationDate, Tags, AcceptedAnswerId, ClosedDate, OwnerReputation, UpvoteCount FROM duplicate_qs
),
comment_stats AS (
    SELECT
        c.PostId                                     AS QuestionId,
        COUNT(*)                                     AS TotalComments,
        STRING_AGG(DISTINCT c.UserDisplayName, ', ') AS CommenterList
    FROM Comments c
    WHERE c.PostId IN (SELECT QuestionId FROM combined)
    GROUP BY c.PostId
),
answer_stats AS (
    SELECT
        a.ParentId                                   AS QuestionId,
        COUNT(*)                                     AS AnswerCount,
        AVG(a.Score)                                 AS AvgAnswerScore,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswerUpvotes
    FROM Posts a
    LEFT JOIN Votes v ON v.PostId = a.Id AND v.VoteTypeId = 2
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
final AS (
    SELECT
        c.QuestionId,
        c.Title,
        c.CreationDate,
        c.Tags,
        c.AcceptedAnswerId,
        c.ClosedDate,
        c.OwnerReputation,
        COALESCE(c.UpvoteCount, 0)                     AS UpvoteCount,
        cs.TotalComments,
        cs.CommenterList,
        as_ans.AnswerCount,
        as_ans.AvgAnswerScore,
        as_ans.AnswerUpvotes,
        (SELECT COUNT(*) FROM Votes v2
         WHERE v2.PostId = c.QuestionId AND v2.VoteTypeId = 2) AS PostUpvotes,
        ROW_NUMBER() OVER (PARTITION BY c.QuestionId
                           ORDER BY COALESCE(as_ans.AnswerUpvotes, 0) DESC) AS RankByAnsUpvotes
    FROM combined c
    LEFT JOIN comment_stats cs ON cs.QuestionId = c.QuestionId
    LEFT JOIN answer_stats as_ans ON as_ans.QuestionId = c.QuestionId
)
SELECT *
FROM final
WHERE RankByAnsUpvotes = 1
ORDER BY AvgAnswerScore DESC NULLS LAST,
         PostUpvotes DESC,
         CreationDate DESC
LIMIT 100;