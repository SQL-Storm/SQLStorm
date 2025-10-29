-- {"query": "3176.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2105} 

/*  Benchmark query: top users by reputation with their best‑scoring answer per tag,
   badge counts, recent activity, question status, and vote balance. */
WITH 
-- 1. Rank users by reputation
UserRank AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
    FROM Users u
    WHERE u.Reputation IS NOT NULL
),

-- 2. Aggregate badge counts per user
BadgeAgg AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),

-- 3. Split answer tags and rank answers per user‑tag pair by score
TagAnswerRank AS (
    SELECT 
        a.OwnerUserId           AS UserId,
        t.Tag,
        a.Id                    AS AnswerId,
        a.CreationDate,
        a.Score,
        ROW_NUMBER() OVER (
            PARTITION BY a.OwnerUserId, t.Tag 
            ORDER BY a.Score DESC, a.CreationDate ASC
        ) AS TagRank
    FROM Posts a
    CROSS JOIN LATERAL (
        SELECT UNNEST(
            STRING_TO_ARRAY(
                TRIM(BOTH '<>' FROM a.Tags), '><'
            )
        ) AS Tag
    ) t
    WHERE a.PostTypeId = 2                -- answers only
      AND a.Tags IS NOT NULL
),

-- 4. Latest activity (posts & comments) per user
UserActivity AS (
    SELECT 
        u.Id                                   AS UserId,
        MAX(p.LastActivityDate)                AS LastPostActivity,
        MAX(c.CreationDate)                    AS LastCommentActivity
    FROM Users u
    LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId      = u.Id
    GROUP BY u.Id
),

-- 5. Vote aggregates per post
PostVoteAgg AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),

-- 6. Determine if the question owning an answer is closed
AnswerQuestionStatus AS (
    SELECT 
        a.AnswerId,
        q.Id                AS QuestionId,
        q.ClosedDate,
        CASE WHEN q.ClosedDate IS NULL THEN 'Open' ELSE 'Closed' END AS QuestionStatus
    FROM TagAnswerRank a
    JOIN Posts q ON q.Id = a.AnswerId AND q.PostTypeId = 1   -- the answer's parent question
)

SELECT
    ur.Id,
    ur.DisplayName,
    ur.Reputation,
    COALESCE(ba.GoldBadges,   0) AS GoldBadges,
    COALESCE(ba.SilverBadges, 0) AS SilverBadges,
    COALESCE(ba.BronzeBadges, 0) AS BronzeBadges,
    ua.LastPostActivity,
    ua.LastCommentActivity,
    tar.Tag,
    tar.AnswerId,
    tar.Score,
    CASE 
        WHEN tar.Score > 0 THEN 'Positive' 
        WHEN tar.Score = 0 THEN 'Zero' 
        ELSE 'Negative' 
    END AS ScoreSign,
    aqs.QuestionStatus,
    COALESCE(pv.UpVotes,   0) - COALESCE(pv.DownVotes, 0) AS VoteBalance
FROM UserRank ur
LEFT JOIN BadgeAgg          ba  ON ba.UserId    = ur.Id
LEFT JOIN UserActivity      ua  ON ua.UserId    = ur.Id
LEFT JOIN TagAnswerRank    tar ON tar.UserId   = ur.Id AND tar.TagRank = 1
LEFT JOIN AnswerQuestionStatus aqs ON aqs.AnswerId = tar.AnswerId
LEFT JOIN PostVoteAgg      pv  ON pv.PostId   = tar.AnswerId
WHERE ur.rn <= 10                     -- top‑10 users
ORDER BY ur.Reputation DESC,
         tar.Score DESC NULLS LAST
LIMIT 10

UNION ALL

/* Separator row for visual clarity in benchmark output */
SELECT 
    NULL, '---', NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL;
