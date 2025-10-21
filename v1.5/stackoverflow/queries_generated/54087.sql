-- {"query": "54087.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 4205} 
WITH
    questions AS (
        SELECT 
            p.Id AS qid,
            p.Title,
            p.Tags,
            p.FavoriteCount,
            p.Score,
            p.AnswerCount,
            p.ViewCount,
            p.OwnerUserId
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),
    tag_listing AS (
        SELECT 
            q.qid,
            UNNEST(regexp_split_to_array(q.Tags, '\<\>|\<|\>')) AS tag
        FROM questions q
    ),
    tag_stats AS (
        SELECT 
            t.qid,
            t.tag,
            COUNT(*) OVER (PARTITION BY t.tag) AS total_questions,
            ROW_NUMBER() OVER (PARTITION BY t.tag ORDER BY t.qid DESC) AS tag_rank
        FROM tag_listing t
    ),
    edit_counts AS (
        SELECT 
            ph.PostId,
            COUNT(*) AS edit_cnt
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (5,6)          -- Edit Body / Tags
        GROUP BY ph.PostId
    ),
    duplicate_counts AS (
        SELECT 
            pl.PostId,
            COUNT(*) AS dup_cnt
        FROM PostLinks pl
        WHERE pl.LinkTypeId = 3                       -- Duplicate
        GROUP BY pl.PostId
    ),
    vote_sums AS (
        SELECT 
            v.PostId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes,
            SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS accepted_votes
        FROM Votes v
        GROUP BY v.PostId
    ),
    user_meta AS (
        SELECT 
            u.Id AS uid,
            u.Reputation,
            u.Views,
            u.UpVotes,
            u.DownVotes
        FROM Users u
    )
SELECT
    q.qid,
    q.Title,
    q.Score,
    q.AnswerCount,
    q.ViewCount,
    q.FavoriteCount,
    u.uid,
    u.Reputation,
    u.Views,
    vs.up_votes,
    vs.down_votes,
    vs.accepted_votes,
    ec.edit_cnt,
    dc.dup_cnt,
    ts.total_questions,
    ts.tag_rank,
    ts.tag
FROM questions q
LEFT JOIN user_meta u ON u.uid = q.OwnerUserId
LEFT JOIN vote_sums vs ON vs.PostId = q.qid
LEFT JOIN edit_counts ec ON ec.PostId = q.qid
LEFT JOIN duplicate_counts dc ON dc.PostId = q.qid
LEFT JOIN tag_stats ts ON ts.qid = q.qid
ORDER BY q.Score DESC, q.AnswerCount DESC, q.ViewCount DESC
LIMIT 5000;