-- {"query": "24049.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 6701} 
WITH question_stats AS (
    SELECT p.Id AS qid,
           p.Title,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           p.AnswerCount,
           u.Id AS uid,
           u.Reputation,
           u.DisplayName,
           u.Location,
           COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS upvotes,
           COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS downvotes,
           COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 1) AS accepted
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount,
             u.Id, u.Reputation, u.DisplayName, u.Location
),
tag_rank AS (
    SELECT p.Id AS qid,
           array_agg(tagname ORDER BY tagname) AS tags_list
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(REGEXP_REPLACE(p.Tags, '[<>]', '', 'g'), '><')) AS tagname
    ) AS tg
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
),
closed_cases AS (
    SELECT ph.PostId,
           COUNT(*) AS close_votes,
           MAX(ph.CreationDate) AS last_close
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),
answers AS (
    SELECT a.ParentId AS qid,
           a.Id AS aid,
           u.Id AS uid
    FROM Posts a
    JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2
),
num_answers AS (
    SELECT qid, COUNT(*) AS n_answers
    FROM answers
    GROUP BY qid
),
answer_users AS (
    SELECT DISTINCT uid FROM answers
),
question_users AS (
    SELECT DISTINCT owneruserId AS uid FROM Posts WHERE PostTypeId = 1
),
active_users AS (
    SELECT uid FROM answer_users
    UNION ALL
    SELECT uid FROM question_users
),
active_user_counts AS (
    SELECT uid, COUNT(*) AS activity_cnt
    FROM active_users
    GROUP BY uid
),
top_questions AS (
    SELECT q.*,
           COALESCE(tc.tags_list, '{}'::varchar[]) AS tags_list,
           COALESCE(cc.close_votes,0) AS close_votes,
           cc.last_close,
           RANK() OVER (ORDER BY q.Score DESC, q.ViewCount DESC) AS overall_rank,
           COALESCE(na.n_answers,0) AS n_answers
    FROM question_stats q
    LEFT JOIN tag_rank tc ON tc.qid = q.qid
    LEFT JOIN closed_cases cc ON cc.PostId = q.qid
    LEFT JOIN num_answers na ON na.qid = q.qid
)
SELECT
    tq.qid,
    tq.Title,
    tq.CreationDate,
    tq.Score,
    tq.ViewCount,
    tq.AnswerCount,
    tq.Reputation,
    tq.Location,
    tq.tags_list,
    tq.upvotes,
    tq.downvotes,
    tq.upvotes - tq.downvotes AS net_votes,
    CASE 
        WHEN tq.last_close IS NOT NULL THEN 'Closed'
        WHEN tq.n_answers > 0 THEN 'Answered'
        ELSE 'Unanswered'
    END AS status,
    COALESCE(au.activity_cnt,0) AS owner_activity_cnt,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = tq.qid) AS comment_cnt,
    COUNT(DISTINCT l.RelatedPostId) FILTER (WHERE l.LinkTypeId = 3) AS duplicate_links,
    COUNT(DISTINCT l.RelatedPostId) FILTER (WHERE l.LinkTypeId = 1) AS linked_posts
FROM top_questions tq
LEFT JOIN active_user_counts au ON au.uid = tq.uid
LEFT JOIN PostLinks l ON l.PostId = tq.qid
GROUP BY tq.qid, tq.Title, tq.CreationDate, tq.Score, tq.ViewCount, tq.AnswerCount,
         tq.Reputation, tq.Location, tq.tags_list, tq.upvotes, tq.downvotes,
         tq.last_close, tq.n_answers, au.activity_cnt
ORDER BY tq.overall_rank
LIMIT 20;