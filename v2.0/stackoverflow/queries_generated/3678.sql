-- {"query": "3678.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2655} 

WITH
/* ------------------------------------------------------------------
   1️⃣  Per‑user basic stats (questions, answers, scores, badges, etc.)
   ------------------------------------------------------------------ */
UserStats AS (
    SELECT
        u.Id                                   AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END)   AS QuestionScoreSum,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END)   AS AnswerScoreSum,
        MAX(p.LastActivityDate)                                 AS LastActivity,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1)          AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2)          AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3)          AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts      p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges     b ON b.UserId     = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

/* ---------------------------------------------------------------
   2️⃣  Tag usage per user (explode the Tags column, rank tags)
   --------------------------------------------------------------- */
TagUsage AS (
    SELECT
        u.Id                                 AS UserId,
        LOWER(TRIM(t.tag))                   AS Tag,
        COUNT(*)                             AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS rn
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
               AND p.PostTypeId = 1
               AND p.Tags IS NOT NULL
    CROSS JOIN LATERAL regexp_split_to_table(p.Tags, '[><]+') AS t(tag)
    GROUP BY u.Id, LOWER(TRIM(t.tag))
),

TopTags AS (
    SELECT
        UserId,
        STRING_AGG(Tag, ', ') FILTER (WHERE rn <= 3) AS TopTags
    FROM TagUsage
    GROUP BY UserId
),

/* ---------------------------------------------------------------
   3️⃣  Recent voting activity (last 30 days)
   --------------------------------------------------------------- */
RecentVotes AS (
    SELECT
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod')   AS RecentUpVotes,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS RecentDownVotes,
        MAX(v.CreationDate)                         AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.UserId
),

/* ---------------------------------------------------------------
   4️⃣  Correlated sub‑queries for each question post
   --------------------------------------------------------------- */
CorrelatedPosts AS (
    SELECT
        p.OwnerUserId,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveCommentCount,
        (SELECT MAX(c.CreationDate) FROM Comments c WHERE c.PostId = p.Id)      AS LastCommentDate
    FROM Posts p
    WHERE p.PostTypeId = 1
),

/* ---------------------------------------------------------------
   5️⃣  Combine everything, add derived columns & tier logic
   --------------------------------------------------------------- */
Combined AS (
    SELECT
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.QuestionCount,
        us.AnswerCount,
        us.QuestionScoreSum,
        us.AnswerScoreSum,
        us.LastActivity,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        COALESCE(tt.TopTags, '')                     AS TopTags,
        COALESCE(rv.RecentUpVotes,0)                 AS RecentUpVotes,
        COALESCE(rv.RecentDownVotes,0)               AS RecentDownVotes,
        rv.LastVoteDate,
        cp.PositiveCommentCount,
        cp.LastCommentDate,
        CASE
            WHEN us.Reputation > 20000 THEN 'Elite'
            WHEN us.Reputation > 10000 THEN 'Veteran'
            WHEN us.Reputation > 1000  THEN 'Contributor'
            ELSE 'Newbie'
        END                                          AS ReputationTier,
        CASE WHEN us.QuestionCount = 0 THEN NULL
             ELSE ROUND(us.QuestionScoreSum::numeric / us.QuestionCount,2)
        END                                          AS AvgQuestionScore,
        CASE WHEN us.AnswerCount = 0 THEN NULL
             ELSE ROUND(us.AnswerScoreSum::numeric / us.AnswerCount,2)
        END                                          AS AvgAnswerScore
    FROM UserStats us
    LEFT JOIN TopTags          tt ON tt.UserId = us.UserId
    LEFT JOIN RecentVotes      rv ON rv.UserId = us.UserId
    LEFT JOIN CorrelatedPosts  cp ON cp.OwnerUserId = us.UserId
),

/* ---------------------------------------------------------------
   6️⃣  Filtered set, ready for set operators
   --------------------------------------------------------------- */
FilteredSet AS (
    SELECT *
    FROM Combined
    WHERE (ReputationTier <> 'Newbie')
       OR GoldBadges > 0
)

SELECT *
FROM FilteredSet
UNION ALL
SELECT
    Id, DisplayName, Reputation, QuestionCount, AnswerCount,
    QuestionScoreSum, AnswerScoreSum, LastActivity,
    GoldBadges, SilverBadges, BronzeBadges,
    TopTags, RecentUpVotes, RecentDownVotes, LastVoteDate,
    PositiveCommentCount, LastCommentDate, ReputationTier,
    AvgQuestionScore, AvgAnswerScore
FROM FilteredSet
WHERE ReputationTier = 'Veteran'
EXCEPT
SELECT
    Id, DisplayName, Reputation, QuestionCount, AnswerCount,
    QuestionScoreSum, AnswerScoreSum, LastActivity,
    GoldBadges, SilverBadges, BronzeBadges,
    TopTags, RecentUpVotes, RecentDownVotes, LastVoteDate,
    PositiveCommentCount, LastCommentDate, ReputationTier,
    AvgQuestionScore, AvgAnswerScore
FROM FilteredSet
WHERE GoldBadges = 0
ORDER BY Reputation DESC NULLS LAST
LIMIT 100;
