WITH
    usr AS (
        SELECT u.Id,
               u.DisplayName,
               u.Reputation,
               u.CreationDate,
               u.LastAccessDate,
               u.Views,
               u.UpVotes,
               u.DownVotes,
               COALESCE(u.Location, 'Unknown') AS Location,
               ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rep_rank
        FROM Users u
    ),
    badge_counts AS (
        SELECT b.UserId,
               COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold_cnt,
               COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver_cnt,
               COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze_cnt,
               COUNT(*) AS total_cnt
        FROM Badges b
        GROUP BY b.UserId
    ),
    recent_votes AS (
        SELECT v.UserId,
               MAX(v.CreationDate) AS last_vote_dt,
               MAX(vt.Name) AS last_vote_type
        FROM Votes v
        LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.UserId
    ),
    top_tags AS (
        SELECT t.TagName,
               t.Count,
               ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS tag_rank
        FROM Tags t
        WHERE t.IsModeratorOnly = FALSE
        GROUP BY t.TagName, t.Count
    ),
    user_posts AS (
        SELECT p.OwnerUserId AS UserId,
               COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS question_cnt,
               COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS answer_cnt,
               COALESCE(AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END),0) AS avg_question_score,
               COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END),0) AS total_question_views,
               MAX(p.CreationDate) AS latest_post_dt
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    linked_questions AS (
        SELECT pl.PostId AS QId,
               COUNT(CASE WHEN pl.LinkTypeId = 1 THEN 1 END) AS linked_cnt,
               COUNT(CASE WHEN pl.LinkTypeId = 3 THEN 1 END) AS duplicate_cnt
        FROM PostLinks pl
        JOIN Posts p ON pl.PostId = p.Id
        WHERE p.PostTypeId = 1
        GROUP BY pl.PostId
    )
SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.rep_rank,
    COALESCE(bc.gold_cnt,0)      AS gold_badges,
    COALESCE(bc.silver_cnt,0)    AS silver_badges,
    COALESCE(bc.bronze_cnt,0)    AS bronze_badges,
    COALESCE(rv.last_vote_dt, CAST('1970-01-01' AS timestamp)) AS last_vote_date,
    COALESCE(rv.last_vote_type, 'None')               AS last_vote_type,
    up.question_cnt,
    up.answer_cnt,
    ROUND(CAST(up.avg_question_score AS numeric),2)           AS avg_q_score,
    up.total_question_views,
    up.latest_post_dt,
    COALESCE(lq.linked_cnt,0)     AS linked_questions,
    COALESCE(lq.duplicate_cnt,0)  AS duplicate_questions,
    CASE
        WHEN u.Reputation > 20000 THEN 'Legendary'
        WHEN u.Reputation > 10000 THEN 'Expert'
        WHEN u.Reputation > 5000  THEN 'Advanced'
        ELSE 'Novice'
    END                           AS reputation_tier,
    CONCAT(u.DisplayName, ' (', u.Id, ')')           AS user_key,
    tt.TagName,
    tt.Count                                            AS tag_use_count
FROM usr u
LEFT JOIN badge_counts bc   ON bc.UserId = u.Id
LEFT JOIN recent_votes rv   ON rv.UserId = u.Id
LEFT JOIN user_posts up     ON up.UserId = u.Id
LEFT JOIN linked_questions lq ON lq.QId = up.UserId
LEFT JOIN LATERAL (
    SELECT t.TagName, t.Count
    FROM Tags t
    WHERE t.TagName LIKE '%' || u.DisplayName || '%'
    ORDER BY t.Count DESC
    LIMIT 1
) tt ON TRUE
WHERE u.rep_rank <= 100

UNION ALL

SELECT
    NULL AS Id,
    'Aggregates' AS DisplayName,
    NULL AS Reputation,
    NULL AS rep_rank,
    SUM(COALESCE(bc.gold_cnt,0)) AS gold_badges,
    SUM(COALESCE(bc.silver_cnt,0)) AS silver_badges,
    SUM(COALESCE(bc.bronze_cnt,0)) AS bronze_badges,
    NULL AS last_vote_date,
    NULL AS last_vote_type,
    SUM(COALESCE(up.question_cnt,0)) AS question_cnt,
    SUM(COALESCE(up.answer_cnt,0)) AS answer_cnt,
    NULL AS avg_q_score,
    NULL AS total_question_views,
    NULL AS latest_post_dt,
    NULL AS linked_questions,
    NULL AS duplicate_questions,
    NULL AS reputation_tier,
    NULL AS user_key,
    NULL AS TagName,
    NULL AS tag_use_count
FROM badge_counts bc
FULL JOIN user_posts up ON up.UserId = bc.UserId;