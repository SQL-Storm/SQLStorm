WITH question_posts AS (
    SELECT Id, Tags, Score, OwnerUserId
    FROM Posts
    WHERE PostTypeId = 1
),
exploded_tags AS (
    SELECT qp.Id AS question_id,
           qp.OwnerUserId,
           t AS tag,
           qp.Score
    FROM question_posts qp
    CROSS JOIN LATERAL regexp_split_to_table(
            SUBSTRING(qp.Tags FROM 2 FOR CHAR_LENGTH(qp.Tags) - 2),
            '><') AS t
),
answer_stats AS (
    SELECT ParentId AS qid,
           COUNT(*) AS answer_cnt,
           AVG(Score) AS avg_ans_score
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
),
comment_stats AS (
    SELECT PostId AS qid,
           COUNT(*) AS comment_cnt
    FROM Comments
    GROUP BY PostId
),
vote_stats AS (
    SELECT PostId,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
           COUNT(*) AS total_votes
    FROM Votes
    GROUP BY PostId
)
SELECT
    et.tag,
    COUNT(DISTINCT et.question_id) AS question_count,
    SUM(a.answer_cnt) AS total_answers,
    AVG(a.avg_ans_score) AS avg_answer_score,
    SUM(cs.comment_cnt) AS total_comments,
    AVG(cs.comment_cnt) AS avg_comments_per_question,
    AVG(u.Reputation) AS avg_user_rep,
    MAX(u.Reputation) AS max_user_rep,
    MIN(u.Reputation) AS min_user_rep,
    ROUND(100.0 * SUM(vs.upvotes) / NULLIF(SUM(vs.total_votes), 0), 2) AS upvote_pct
FROM exploded_tags et
JOIN answer_stats a ON a.qid = et.question_id
JOIN comment_stats cs ON cs.qid = et.question_id
JOIN vote_stats vs ON vs.PostId = et.question_id
JOIN Users u ON u.Id = et.OwnerUserId
GROUP BY et.tag
ORDER BY question_count DESC
LIMIT 20;