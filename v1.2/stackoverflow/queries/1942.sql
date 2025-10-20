WITH PostRepliesWithRank AS (
    SELECT
        p.owneruserid AS Account,
        p.id,
        p.parentid,
        p.score,
        p.creationdate,
        ROW_NUMBER() OVER (PARTITION BY p.parentid ORDER BY p.score DESC, p.creationdate ASC) AS reply_rank
    FROM Posts p
    WHERE p.posttypeid = 2
),
QuestionsWithTopReply AS (
    SELECT
        q.id AS QuestionId,
        q.owneruserid AS QuestionOwnerId,
        q.score AS QuestionScore,
        q.creationdate AS QuestionCreationDate,
        tr.id   AS TopReplyId,
        tr.account AS TopReplyAccount,
        tr.score AS TopReplyScore,
        tr.creationdate AS TopReplyCreationDate
    FROM Posts q
    LEFT JOIN PostRepliesWithRank tr
        ON tr.parentid = q.id
        AND tr.reply_rank = 1
    WHERE q.posttypeid = 1
)
SELECT
    q.QuestionId,
    q.QuestionOwnerId,
    q.QuestionScore,
    q.QuestionCreationDate,
    q.TopReplyId,
    q.TopReplyAccount,
    q.TopReplyScore,
    q.TopReplyCreationDate
FROM QuestionsWithTopReply q
ORDER BY q.QuestionCreationDate DESC;