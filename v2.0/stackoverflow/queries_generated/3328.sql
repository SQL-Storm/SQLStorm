-- {"query": "3328.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1885} 

/* 1️⃣  CTEs for heavy lifting */
WITH
    /* User activity aggregation */
    usr_stats AS (
        SELECT
            u.Id                                 AS user_id,
            u.DisplayName                        AS display_name,
        /* reputation may be null in bizarre edge‑cases */
            COALESCE(u.Reputation, 0)            AS reputation,
            COUNT(DISTINCT q.Id)                 AS questions_posted,
            COUNT(DISTINCT a.Id)                 AS answers_posted,
            COALESCE(SUM(CASE
                WHEN v.VoteTypeId = 2 THEN  1   /* upvote  */
                WHEN v.VoteTypeId = 3 THEN -1   /* downvote*/
                ELSE 0
            END),0)                             AS vote_balance,
            MAX(u.LastAccessDate)               AS last_seen
        FROM Users u
        LEFT JOIN Posts q   ON q.OwnerUserId = u.Id AND q.PostTypeId = 1
        LEFT JOIN Posts a   ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
        LEFT JOIN Votes v   ON v.PostId IN (q.Id, a.Id) AND v.VoteTypeId IN (2,3)
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),

    /* Badge points per user (gold=1000, silver=500, bronze=100) */
    badge_pts AS (
        SELECT
            b.UserId                       AS user_id,
            SUM(CASE b.Class
                WHEN 1 THEN 1000
                WHEN 2 THEN 500
                ELSE 100
            END)                           AS badge_score
        FROM Badges b
        GROUP BY b.UserId
    ),

    /* Top 10 tags by usage, ranked */
    top_tags AS (
        SELECT
            t.TagName,
            t.Count,
            ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS tag_rank
        FROM Tags t
        WHERE t.IsModeratorOnly = 0
    ),

    /* Latest closed‑question info (if any) */
    recent_closed AS (
        SELECT
            ph.PostId,
            ph.CreationDate                AS closed_at,
            TRY_CAST(ph.Comment AS int)    AS close_reason_id
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10          /* Post Closed */
          AND ph.CreationDate > CURRENT_DATE - INTERVAL '30 days'
    ),

    /* Correlated sub‑query to pull the best answer per question */
    best_answer AS (
        SELECT
            q.Id                           AS question_id,
            a.Id                           AS best_answer_id,
            a.Score                        AS best_score,
            a.CreationDate                 AS answered_on
        FROM Posts q
        LEFT JOIN LATERAL (
            SELECT
                ans.Id,
                ans.Score,
                ans.CreationDate
            FROM Posts ans
            WHERE ans.ParentId = q.Id
              AND ans.PostTypeId = 2
            ORDER BY ans.Score DESC NULLS LAST, ans.CreationDate ASC
            LIMIT 1
        ) a ON true
        WHERE q.PostTypeId = 1
    ),

    /* Unioned set of high‑impact posts (score ≥ 100 OR favorite ≥ 10) */
    high_impact_posts AS (
        SELECT
            p.Id,
            p.Title,
            p.Score,
            p.FavoriteCount,
            p.OwnerUserId,
            p.CreationDate
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND (p.Score >= 100 OR COALESCE(p.FavoriteCount,0) >= 10)

        UNION ALL

        SELECT
            p.Id,
            p.Title,
            p.Score,
            p.FavoriteCount,
            p.OwnerUserId,
            p.CreationDate
        FROM Posts p
        WHERE p.PostTypeId = 2
          AND EXISTS (
                SELECT 1 FROM Votes v
                WHERE v.PostId = p.Id
                  AND v.VoteTypeId = 2
                GROUP BY v.PostId
                HAVING COUNT(*) >= 50
          )
    )
/* 2️⃣  Main SELECT pulling everything together */
SELECT
    us.user_id,
    us.display_name,
    us.reputation,
    us.questions_posted,
    us.answers_posted,
    us.vote_balance,
    COALESCE(bp.badge_score,0)                AS badge_score,
    /* Overall activity index – weighted sum */
    (us.reputation * 0.4
     + us.questions_posted * 5
     + us.answers_posted   * 10
     + us.vote_balance    * 2
     + COALESCE(bp.badge_score,0) * 0.01)    AS activity_index,
    /* Latest closed‑question (if any) */
    rc.closed_at,
    rc.close_reason_id,
    /* Best answer for the last question this user asked */
    ba.best_answer_id,
    ba.best_score,
    ba.answered_on,
    /* Concatenated list of top‑3 tags (comma‑separated) */
    STRING_AGG(tt.TagName, ', ') FILTER (WHERE tt.tag_rank <= 3) OVER (PARTITION BY us.user_id) AS top_three_tags,
    /* Count of high‑impact posts owned */
    COUNT(hip.Id) FILTER (WHERE hip.OwnerUserId = us.user_id) OVER (PARTITION BY us.user_id) AS high_impact_post_cnt,
    /* Flag if user has never been seen in last 90 days */
    CASE WHEN us.last_seen < CURRENT_DATE - INTERVAL '90 days' THEN 1 ELSE 0 END AS dormant_flag
FROM usr_stats us
LEFT JOIN badge_pts bp      ON bp.user_id = us.user_id
LEFT JOIN recent_closed rc ON rc.PostId = (
        SELECT q.Id
        FROM Posts q
        WHERE q.OwnerUserId = us.user_id
          AND q.PostTypeId = 1
        ORDER BY q.CreationDate DESC
        LIMIT 1
    )
LEFT JOIN best_answer ba    ON ba.question_id = (
        SELECT q.Id
        FROM Posts q
        WHERE q.OwnerUserId = us.user_id
          AND q.PostTypeId = 1
        ORDER BY q.CreationDate DESC
        LIMIT 1
    )
LEFT JOIN top_tags tt       ON TRUE          /* cross‑join to allow window aggregation */
LEFT JOIN high_impact_posts hip ON hip.OwnerUserId = us.user_id
GROUP BY
    us.user_id, us.display_name, us.reputation,
    us.questions_posted, us.answers_posted, us.vote_balance,
    bp.badge_score, rc.closed_at, rc.close_reason_id,
    ba.best_answer_id, ba.best_score, ba.answered_on,
    us.last_seen
HAVING COUNT(hip.Id) FILTER (WHERE hip.OwnerUserId = us.user_id) > 0
ORDER BY activity_index DESC
LIMIT 100;
