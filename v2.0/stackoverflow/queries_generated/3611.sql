-- {"query": "3611.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1855} 

/*  Benchmark query: deep analytics on users, their posts, tags, badges and votes  */
WITH
/* 1. All questions (PostTypeId = 1) with their top‑3 tags extracted */
question_tags AS (
    SELECT
        p.Id               AS QuestionId,
        p.OwnerUserId      AS OwnerUserId,
        p.CreationDate    AS QCreation,
        p.Score           AS QScore,
        p.ViewCount       AS QViews,
        CASE 
            WHEN p.Tags IS NULL THEN NULL
            ELSE regexp_split_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')
        END                AS TagArray
    FROM Posts p
    WHERE p.PostTypeId = 1
),
question_tags_flat AS (
    SELECT
        qt.QuestionId,
        qt.OwnerUserId,
        qt.QCreation,
        qt.QScore,
        qt.QViews,
        UNNEST(qt.TagArray) AS TagName
    FROM question_tags qt
    WHERE qt.TagArray IS NOT NULL
),
top_question_tags AS (
    SELECT
        qtf.OwnerUserId,
        qtf.TagName,
        COUNT(*)                                  AS TagUseCount,
        ROW_NUMBER() OVER (PARTITION BY qtf.OwnerUserId ORDER BY COUNT(*) DESC) AS rn
    FROM question_tags_flat qtf
    GROUP BY qtf.OwnerUserId, qtf.TagName
),
user_top_tags AS (
    SELECT
        OwnerUserId,
        STRING_AGG(TagName, ', ') FILTER (WHERE rn <= 3) AS Top3Tags
    FROM top_question_tags
    GROUP BY OwnerUserId
),

/* 2. Badge aggregation per user */
badge_counts AS (
    SELECT
        b.UserId,
        COUNT(*)                                 AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, ', ')        AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
),

/* 3. Vote statistics per user (both as post owner and as voter) */
owner_vote_stats AS (
    SELECT
        p.OwnerUserId                                    AS UserId,
        COUNT(v.Id)                                      AS VotesOnOwnPosts,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesOnOwn,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesOnOwn,
        AVG(v.CreationDate::date - p.CreationDate::date)  AS AvgDaysToFirstVote
    FROM Posts p
    JOIN Votes v ON v.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
voter_vote_stats AS (
    SELECT
        v.UserId,
        COUNT(v.Id)                                      AS VotesCast,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCast,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCast,
        MAX(v.CreationDate)                              AS LastVoteDate
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),

/* 4. Recent activity (most recent post, comment, or vote) per user */
latest_activity AS (
    SELECT
        u.Id                                                     AS UserId,
        GREATEST(
            COALESCE((SELECT MAX(CreationDate) FROM Posts   WHERE OwnerUserId = u.Id), '1970-01-01'::timestamp),
            COALESCE((SELECT MAX(CreationDate) FROM Comments WHERE UserId      = u.Id), '1970-01-01'::timestamp),
            COALESCE((SELECT MAX(CreationDate) FROM Votes    WHERE UserId      = u.Id), '1970-01-01'::timestamp)
        )                                                       AS LastActivityDate
    FROM Users u
),

/* 5. Users with no badges but high reputation (set operator example) */
high_rep_no_badge AS (
    SELECT u.Id
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE b.Id IS NULL AND u.Reputation > 20000
    UNION ALL
    SELECT u.Id
    FROM Users u
    WHERE NOT EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id)
      AND u.Reputation > 20000
),

/* 6. Correlated sub‑query to fetch the most recent accepted answer per question */
recent_accepted_answer AS (
    SELECT
        q.Id                                      AS QuestionId,
        a.Id                                      AS AnswerId,
        a.CreationDate                            AS AnswerDate,
        a.Score                                   AS AnswerScore
    FROM Posts q
    LEFT JOIN LATERAL (
        SELECT *
        FROM Posts a
        WHERE a.PostTypeId = 2
          AND a.ParentId = q.Id
          AND a.Id = q.AcceptedAnswerId
        ORDER BY a.CreationDate DESC
        LIMIT 1
    ) a ON true
    WHERE q.PostTypeId = 1
)

SELECT
    u.Id                                   AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(bc.TotalBadges, 0)            AS TotalBadges,
    COALESCE(bc.GoldBadges, 0)             AS GoldBadges,
    COALESCE(bc.SilverBadges, 0)           AS SilverBadges,
    COALESCE(bc.BronzeBadges, 0)           AS BronzeBadges,
    bc.BadgeList,
    COALESCE(ut.Top3Tags, '')              AS TopThreeTags,
    COALESCE(ovs.VotesOnOwnPosts,0)        AS VotesOnOwnPosts,
    COALESCE(ovs.UpVotesOnOwn,0)           AS UpVotesOnOwn,
    COALESCE(ovs.DownVotesOnOwn,0)         AS DownVotesOnOwn,
    ROUND(COALESCE(ovs.AvgDaysToFirstVote,0),2) AS AvgDaysToFirstVote,
    COALESCE(vvs.VotesCast,0)              AS VotesCast,
    COALESCE(vvs.UpVotesCast,0)            AS UpVotesCast,
    COALESCE(vvs.DownVotesCast,0)          AS DownVotesCast,
    vvs.LastVoteDate,
    la.LastActivityDate,
    CASE 
        WHEN hn.Id IS NOT NULL THEN 'HighRepNoBadge' 
        ELSE NULL 
    END                                   AS FlagHighRepNoBadge,
    /* 7. Include a window function to rank users by reputation within their badge class */
    RANK() OVER (PARTITION BY COALESCE(bc.GoldBadges,0) 
                 ORDER BY u.Reputation DESC) AS RepRankInGoldClass
FROM Users u
LEFT JOIN badge_counts bc      ON bc.UserId = u.Id
LEFT JOIN user_top_tags ut    ON ut.OwnerUserId = u.Id
LEFT JOIN owner_vote_stats ovs ON ovs.UserId = u.Id
LEFT JOIN voter_vote_stats vvs ON vvs.UserId = u.Id
LEFT JOIN latest_activity la   ON la.UserId = u.Id
LEFT JOIN high_rep_no_badge hn ON hn.Id = u.Id
WHERE u.CreationDate < CURRENT_DATE - INTERVAL '1 year'   -- exclude brand‑new users
  AND (u.Reputation > 1000 OR bc.TotalBadges > 0)        -- keep active participants
ORDER BY u.Reputation DESC
LIMIT 1000;
