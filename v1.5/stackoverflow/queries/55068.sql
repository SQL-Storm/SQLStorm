-- {"query": "55068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1601} 
WITH TagStats AS (
    SELECT
        t.tag,
        p.Id                     AS post_id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.ViewCount,
        p.FavoriteCount,
        COALESCE(v.up_votes, 0)   AS up_votes,
        COALESCE(v.down_votes,0)  AS down_votes,
        ph_closure.CreationDate   AS close_date
    FROM Posts p
    JOIN LATERAL unnest(
            string_to_array(
                trim(both '<>' FROM p.Tags),
                '><'
            )
        ) AS t(tag) ON true
    LEFT JOIN (
        SELECT
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes
        FROM Votes
        GROUP BY PostId
    ) v ON v.PostId = p.Id
    LEFT JOIN PostHistory ph_closure
        ON ph_closure.PostId = p.Id
        AND ph_closure.PostHistoryTypeId = 10   -- Post Closed
    WHERE p.PostTypeId = 1                     -- Questions only
),
UserAgg AS (
    SELECT
        tag,
        OwnerUserId                           AS user_id,
        COUNT(*)                              AS question_count,
        SUM(Score)                            AS total_score,
        SUM(ViewCount)                        AS total_views,
        SUM(FavoriteCount)                    AS total_favorites,
        SUM(up_votes)                         AS total_up_votes,
        SUM(down_votes)                       AS total_down_votes,
        MAX(CreationDate)                     AS most_recent_question
    FROM TagStats
    GROUP BY tag, OwnerUserId
),
UserBadge AS (
    SELECT
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS gold_badges,
        COUNT(*) FILTER (WHERE Class = 2) AS silver_badges,
        COUNT(*) FILTER (WHERE Class = 3) AS bronze_badges
    FROM Badges
    GROUP BY UserId
),
UserReputation AS (
    SELECT
        Id   AS user_id,
        Reputation,
        CreationDate AS user_since
    FROM Users
),
TopTagUsers AS (
    SELECT
        ua.tag,
        ua.user_id,
        u.DisplayName,
        ua.question_count,
        ua.total_score,
        ua.total_views,
        ua.total_favorites,
        ub.gold_badges,
        ub.silver_badges,
        ub.bronze_badges,
        ur.Reputation,
        ROW_NUMBER() OVER (
            PARTITION BY ua.tag
            ORDER BY ua.total_score DESC, ua.total_views DESC
        ) AS rn
    FROM UserAgg ua
    JOIN UserBadge ub   ON ub.UserId = ua.user_id
    JOIN UserReputation ur ON ur.user_id = ua.user_id
    LEFT JOIN Users u    ON u.Id = ua.user_id
)
SELECT
    tag,
    user_id,
    DisplayName,
    question_count,
    total_score,
    total_views,
    total_favorites,
    gold_badges,
    silver_badges,
    bronze_badges,
    Reputation
FROM TopTagUsers
WHERE rn <= 10
ORDER BY tag, rn;