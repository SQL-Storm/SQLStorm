-- {"query": "3543.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2018} 

/*  Complex benchmark query for the StackOverflow schema  */
WITH 
/* Recent questions (last 30 days) */
recent_questions AS (
    SELECT 
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.OwnerUserId,
        u.DisplayName,
        u.Reputation,
        u.Id AS UserId
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1                      -- only questions
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),

/* Tags that are very popular (Count > 5000) */
popular_tags AS (
    SELECT TagName
    FROM Tags
    WHERE Count > 5000
),

/* Flag questions that contain at least one popular tag */
question_tag_flag AS (
    SELECT 
        rq.*,
        CASE 
            WHEN EXISTS (
                SELECT 1
                FROM unnest(string_to_array(rq.Tags, '><')) AS t(tag)
                WHERE t.tag = ANY (SELECT TagName FROM popular_tags)
            ) THEN 1 
            ELSE 0 
        END AS HasPopularTag
    FROM recent_questions rq
),

/* Aggregate votes per post (net score & favorite count) */
vote_aggregation AS (
    SELECT 
        v.PostId,
        SUM(CASE 
                WHEN v.VoteTypeId = 2 THEN 1   -- UpMod
                WHEN v.VoteTypeId = 3 THEN -1  -- DownMod
                ELSE 0
            END) AS NetScore,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS FavoriteCount
    FROM Votes v
    GROUP BY v.PostId
),

/* Badge counts per user (Gold / Silver / Bronze) */
badge_counts AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),

/* Rank questions within each post type by original Score */
ranked_questions AS (
    SELECT 
        qtf.*,
        COALESCE(vag.NetScore, 0)      AS NetScore,
        COALESCE(vag.FavoriteCount,0)  AS FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY qtf.Score DESC) 
                                      AS RankByScore,
        bc.GoldBadges,
        bc.SilverBadges,
        bc.BronzeBadges,
        /* Correlated scalar sub‑query: average vote type of this user */
        (SELECT AVG(v2.VoteTypeId)::numeric 
         FROM Votes v2 
         WHERE v2.UserId = qtf.UserId) AS AvgUserVoteType
    FROM question_tag_flag qtf
    LEFT JOIN vote_aggregation vag ON qtf.Id = vag.PostId
    LEFT JOIN Posts p ON qtf.Id = p.Id
    LEFT JOIN badge_counts bc ON qtf.UserId = bc.UserId
)

/* Final result set – union of top‑ranked and broader set */
SELECT 
    rq.Id,
    rq.Title,
    rq.CreationDate,
    rq.Score,
    rq.NetScore,
    rq.FavoriteCount,
    rq.HasPopularTag,
    rq.DisplayName,
    rq.Reputation,
    rq.GoldBadges,
    rq.SilverBadges,
    rq.BronzeBadges,
    rq.AvgUserVoteType,
    CASE WHEN rq.RankByScore <= 10 THEN 'Top10' ELSE NULL END AS RankFlag
FROM ranked_questions rq
WHERE rq.HasPopularTag = 1
  AND rq.Score > 5

UNION ALL

SELECT 
    rq.Id,
    rq.Title,
    rq.CreationDate,
    rq.Score,
    rq.NetScore,
    rq.FavoriteCount,
    rq.HasPopularTag,
    rq.DisplayName,
    rq.Reputation,
    rq.GoldBadges,
    rq.SilverBadges,
    rq.BronzeBadges,
    rq.AvgUserVoteType,
    NULL AS RankFlag
FROM ranked_questions rq
WHERE rq.HasPopularTag = 0
  AND rq.RankByScore <= 5

ORDER BY Score DESC, NetScore DESC
LIMIT 100;
