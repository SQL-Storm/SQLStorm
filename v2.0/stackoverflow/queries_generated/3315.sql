-- {"query": "3315.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2718} 

/*  Complex performance‑benchmark query on the StackOverflow schema  */
WITH
/*--------------------------------------------------------------
  1.  Basic per‑user statistics (badges, posts, answer scores)
 --------------------------------------------------------------*/
usr_stats AS (
    SELECT
        u.Id                               AS user_id,
        u.DisplayName                      AS display_name,
        u.Reputation,
        COUNT(b.Id)            FILTER (WHERE b.Class = 1) AS gold_badges,
        COUNT(b.Id)            FILTER (WHERE b.Class = 2) AS silver_badges,
        COUNT(b.Id)            FILTER (WHERE b.Class = 3) AS bronze_badges,
        COUNT(b.Id)            FILTER (WHERE b.TagBased = 1) AS tag_based_badges,
        COUNT(p.Id)            FILTER (WHERE p.PostTypeId = 1) AS question_cnt,
        COUNT(p.Id)            FILTER (WHERE p.PostTypeId = 2) AS answer_cnt,
        COUNT(p.Id)            FILTER (WHERE p.PostTypeId = 3) AS wiki_cnt,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS avg_answer_score
    FROM Users u
    LEFT JOIN Badges b   ON b.UserId = u.Id
    LEFT JOIN Posts  p   ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

/*--------------------------------------------------------------
  2.  Distinct tags used in a user’s questions (string parsing)
 --------------------------------------------------------------*/
tag_usage AS (
    SELECT
        q.OwnerUserId                AS user_id,
        COUNT(DISTINCT t.tag)       AS distinct_tag_cnt
    FROM Posts q
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(
                 substring(q.Tags FROM 2 FOR char_length(q.Tags)-2),
                 '><')) AS tag
    ) t
    WHERE q.PostTypeId = 1               -- only questions
      AND q.Tags IS NOT NULL
    GROUP BY q.OwnerUserId
),

/*--------------------------------------------------------------
  3.  Most recent post per user (window function)
 --------------------------------------------------------------*/
recent_post AS (
    SELECT
        p.OwnerUserId               AS user_id,
        p.Title,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                           ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.Title IS NOT NULL
),

/*--------------------------------------------------------------
  4.  Number of closed questions authored (correlated subquery)
 --------------------------------------------------------------*/
closed_q_cnt AS (
    SELECT
        ph.UserId                 AS user_id,
        COUNT(*)                  AS closed_q_cnt
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
    WHERE pht.Name = 'Post Closed'      -- close events
    GROUP BY ph.UserId
),

/*--------------------------------------------------------------
  5.  Votes cast by the user (set operator later)
 --------------------------------------------------------------*/
vote_stats AS (
    SELECT
        v.UserId                  AS user_id,
        COUNT(*) FILTER (WHERE vt.Id = 2) AS upmod_votes,
        COUNT(*) FILTER (WHERE vt.Id = 3) AS downmod_votes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.UserId
),

/*--------------------------------------------------------------
  6.  Aggregate row for the whole site (used in UNION)
 --------------------------------------------------------------*/
site_totals AS (
    SELECT
        NULL                     AS user_id,
        'SITE TOTAL'             AS display_name,
        SUM(u.Reputation)        AS Reputation,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
        SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS tag_based_badges,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_cnt,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_cnt,
        SUM(CASE WHEN p.PostTypeId = 3 THEN 1 ELSE 0 END) AS wiki_cnt,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS avg_answer_score,
        (SELECT COUNT(DISTINCT tag)
         FROM Posts q
         CROSS JOIN LATERAL (
             SELECT unnest(string_to_array(
                      substring(q.Tags FROM 2 FOR char_length(q.Tags)-2),
                      '><')) AS tag
         ) t
         WHERE q.PostTypeId = 1 AND q.Tags IS NOT NULL) AS distinct_tag_cnt,
        NULL AS most_recent_title,
        NULL AS most_recent_date,
        (SELECT COUNT(*) FROM PostHistory ph
         JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
         WHERE pht.Name = 'Post Closed') AS closed_q_cnt,
        (SELECT COUNT(*) FROM Votes v JOIN VoteTypes vt ON vt.Id = v.VoteTypeId WHERE vt.Id = 2) AS upmod_votes,
        (SELECT COUNT(*) FROM Votes v JOIN VoteTypes vt ON vt.Id = v.VoteTypeId WHERE vt.Id = 3) AS downmod_votes,
        1 AS ReputationRank
    FROM Users u
    LEFT JOIN Badges b   ON b.UserId = u.Id
    LEFT JOIN Posts p    ON p.OwnerUserId = u.Id
),

/*--------------------------------------------------------------
  7.  Top users (windowed rank)
 --------------------------------------------------------------*/
ranked_users AS (
    SELECT
        us.user_id,
        us.display_name,
        us.Reputation,
        us.gold_badges,
        us.silver_badges,
        us.bronze_badges,
        us.tag_based_badges,
        us.question_cnt,
        us.answer_cnt,
        us.wiki_cnt,
        COALESCE(us.avg_answer_score,0) AS avg_answer_score,
        COALESCE(tu.distinct_tag_cnt,0) AS distinct_tag_cnt,
        rp.Title                         AS most_recent_title,
        rp.CreationDate                  AS most_recent_date,
        COALESCE(cqc.closed_q_cnt,0)     AS closed_q_cnt,
        COALESCE(vs.upmod_votes,0)       AS upmod_votes,
        COALESCE(vs.downmod_votes,0)     AS downmod_votes,
        RANK() OVER (ORDER BY us.Reputation DESC) AS ReputationRank
    FROM usr_stats us
    LEFT JOIN tag_usage   tu ON tu.user_id = us.user_id
    LEFT JOIN (SELECT * FROM recent_post WHERE rn = 1) rp
           ON rp.user_id = us.user_id
    LEFT JOIN closed_q_cnt cqc ON cqc.user_id = us.user_id
    LEFT JOIN vote_stats   vs  ON vs.user_id = us.user_id
    WHERE us.Reputation > 1000
)

SELECT *
FROM ranked_users
WHERE ReputationRank <= 100
ORDER BY ReputationRank
UNION ALL
SELECT *
FROM site_totals
ORDER BY ReputationRank;
