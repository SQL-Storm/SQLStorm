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
           COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvotes,
           COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS downvotes,
           COUNT(CASE WHEN v.VoteTypeId = 1 THEN 1 END) AS accepted
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount,
             u.Id, u.Reputation, u.DisplayName, u.Location
),
tag_rank AS (
    SELECT p.Id AS qid,
           ARRAY_AGG(tagname ORDER BY tagname) AS tags_list
    FROM Posts p,
         LATERAL (
           SELECT UNNEST(STRING_TO_ARRAY(REGEXP_REPLACE(p.Tags, '[<>]', '', 'g'), '><')) AS tagname
         ) tg
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
    SELECT DISTINCT OwnerUserId AS uid FROM Posts WHERE PostTypeId = 1
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
           COALESCE(tc.tags_list, ARRAY[]::text[]) AS tags_list,
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
    COUNT(DISTINCT CASE WHEN l.LinkTypeId = 3 THEN l.RelatedPostId END) AS duplicate_links,
    COUNT(DISTINCT CASE WHEN l.LinkTypeId = 1 THEN l.RelatedPostId END) AS linked_posts,
    tq.overall_rank
FROM top_questions tq
LEFT JOIN active_user_counts au ON au.uid = tq.uid
LEFT JOIN PostLinks l ON l.PostId = tq.qid
GROUP BY tq.qid, tq.Title, tq.CreationDate, tq.Score, tq.ViewCount, tq.AnswerCount,
         tq.Reputation, tq.Location, tq.tags_list, tq.upvotes, tq.downvotes,
         tq.last_close, tq.n_answers, au.activity_cnt, tq.overall_rank
ORDER BY tq.overall_rank
LIMIT 20;