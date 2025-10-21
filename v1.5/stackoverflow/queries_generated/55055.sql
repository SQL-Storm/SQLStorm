-- {"query": "55055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1807} 

/*  Complex performance‑benchmark query over the StackOverflow schema  */
WITH
/*-----------------------------------------------------------------
  1.  Compute per‑user activity aggregates (posts, answers, comments,
      votes cast, votes received, badge counts) for the last 12 months
-----------------------------------------------------------------*/
user_activity AS (
    SELECT
        u.Id                                 AS user_id,
        u.DisplayName                        AS user_name,
        COUNT(DISTINCT p.Id)                 AS total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS total_answers,
        COUNT(DISTINCT c.Id)                 AS total_comments,
        COUNT(DISTINCT v.Id)                 AS votes_cast,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes_cast,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes_cast,
        COUNT(DISTINCT pv.Id)                AS votes_received,
        SUM(CASE WHEN pv.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes_received,
        SUM(CASE WHEN pv.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes_received,
        COUNT(DISTINCT b.Id)                 AS total_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS gold_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS silver_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS bronze_badges
    FROM Users u
    LEFT JOIN Posts p       ON p.OwnerUserId = u.Id
                              AND p.CreationDate >= CURRENT_DATE - INTERVAL '12 months'
    LEFT JOIN Comments c    ON c.UserId = u.Id
                              AND c.CreationDate >= CURRENT_DATE - INTERVAL '12 months'
    LEFT JOIN Votes v       ON v.UserId = u.Id
                              AND v.CreationDate >= CURRENT_DATE - INTERVAL '12 months'
    LEFT JOIN Votes pv      ON pv.PostId = p.Id
                              AND pv.CreationDate >= CURRENT_DATE - INTERVAL '12 months'
    LEFT JOIN Badges b      ON b.UserId = u.Id
                              AND b.Date >= CURRENT_DATE - INTERVAL '12 months'
    GROUP BY u.Id, u.DisplayName
),

/*-----------------------------------------------------------------
  2.  Identify the top‑5 tags per user by post count (question tags)
-----------------------------------------------------------------*/
user_top_tags AS (
    SELECT
        ua.user_id,
        t.TagName,
        cnt AS tag_post_count,
        ROW_NUMBER() OVER (PARTITION BY ua.user_id ORDER BY cnt DESC) AS rn
    FROM user_activity ua
    JOIN Posts p            ON p.OwnerUserId = ua.user_id
                              AND p.PostTypeId = 1          -- only questions
    CROSS JOIN LATERAL (
        SELECT TRIM(BOTH '<>' FROM UNNEST(string_to_array(p.Tags, '><'))) AS tag
    ) AS tag_split
    JOIN Tags t             ON t.TagName = tag_split.tag
    GROUP BY ua.user_id, t.TagName, cnt
)
,

/*-----------------------------------------------------------------
  3.  Recent high‑scoring posts (score ≥ 50) created in the last 30 days,
      together with their accepted answer (if any) and duplicate links
-----------------------------------------------------------------*/
recent_hot_posts AS (
    SELECT
        p.Id                                 AS question_id,
        p.Title                              AS question_title,
        p.Score                              AS question_score,
        p.CreationDate                       AS question_created,
        a.Id                                 AS accepted_answer_id,
        a.Score                              AS answer_score,
        COALESCE(dup.RelatedPostId, NULL)    AS duplicate_of_question_id,
        dup.CreationDate                     AS duplicate_created
    FROM Posts p
    LEFT JOIN Posts a
           ON a.Id = p.AcceptedAnswerId
    LEFT JOIN PostLinks dup
           ON dup.PostId = p.Id
          AND dup.LinkTypeId = 3               -- Duplicate link
    WHERE p.PostTypeId = 1                     -- questions
      AND p.Score >= 50
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),

/*-----------------------------------------------------------------
  4.  Aggregate vote distribution per vote type for the whole site
-----------------------------------------------------------------*/
vote_distribution AS (
    SELECT
        vt.Name      AS vote_type,
        COUNT(v.Id)  AS total_votes,
        ROUND(100.0 * COUNT(v.Id) / SUM(COUNT(v.Id)) OVER (), 2) AS pct_of_all_votes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY vt.Name
),

/*-----------------------------------------------------------------
  5.  Compute a “user influence score” combining activity, reputation,
      badge weight and recent hot post participation
-----------------------------------------------------------------*/
user_influence AS (
    SELECT
        ua.user_id,
        ua.user_name,
        ua.total_posts,
        ua.total_answers,
        ua.upvotes_received,
        ua.downvotes_received,
        ua.gold_badges * 5 + ua.silver_badges * 3 + ua.bronze_badges * 1 AS badge_weight,
        COALESCE(hp.cnt,0)                                    AS hot_post_participation,
        (   ua.total_posts * 1.2
          + ua.total_answers * 2.5
          + ua.upvotes_received * 0.8
          - ua.downvotes_received * 0.5
          + (ua.gold_badges * 5 + ua.silver_badges * 3 + ua.bronze_badges) * 2
          + COALESCE(hp.cnt,0) * 3
        ) AS influence_score
    FROM user_activity ua
    LEFT JOIN (
        SELECT
            p.OwnerUserId AS uid,
            COUNT(DISTINCT p.Id) AS cnt
        FROM recent_hot_posts rp
        JOIN Posts p ON p.Id = rp.question_id OR p.Id = rp.accepted_answer_id
        GROUP BY p.OwnerUserId
    ) hp ON hp.uid = ua.user_id
),

/*-----------------------------------------------------------------
  6.  Final ranking of top 100 users by influence, with their top tags
-----------------------------------------------------------------*/
final_ranking AS (
    SELECT
        ui.user_id,
        ui.user_name,
        ui.influence_score,
        ui.total_posts,
        ui.total_answers,
        ui.upvotes_received,
        ui.downvotes_received,
        ui.badge_weight,
        ui.hot_post_participation,
        STRING_AGG(utt.TagName, ', ') FILTER (WHERE utt.rn <= 5) AS top_5_tags
    FROM user_influence ui
    LEFT JOIN (
        SELECT *
        FROM user_top_tags
        WHERE rn <= 5
    ) utt ON utt.user_id = ui.user_id
    GROUP BY
        ui.user_id, ui.user_name, ui.influence_score,
        ui.total_posts, ui.total_answers,
        ui.upvotes_received, ui.downvotes_received,
        ui.badge_weight, ui.hot_post_participation
    ORDER BY ui.influence_score DESC
    LIMIT 100
)

SELECT
    fr.rank                           AS user_rank,
    fr.user_name,
    fr.influence_score,
    fr.total_posts,
    fr.total_answers,
    fr.upvotes_received,
    fr.downvotes_received,
    fr.badge_weight,
    fr.hot_post_participation,
    fr.top_5_tags,
    vd.vote_type,
    vd.total_votes,
    vd.pct_of_all_votes
FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY influence_score DESC) AS rank
    FROM final_ranking
) fr
CROSS JOIN vote_distribution vd
ORDER BY fr.rank, vd.vote_type;
