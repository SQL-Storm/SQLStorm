-- {"query": "3940.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2912} 

WITH
/* ------------------------------------------------------------------
   1.  Per‑user aggregated statistics (reputation, net votes, badge counts)
------------------------------------------------------------------- */
UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)               AS NetVotes,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId=u.Id AND b.Class=1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId=u.Id AND b.Class=2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId=u.Id AND b.Class=3) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)               AS RepRank
    FROM Users u
),

/* ------------------------------------------------------------------
   2.  Recent activity per user (last post activity, last comment)
------------------------------------------------------------------- */
RecentActivity AS (
    SELECT
        u.Id,
        MAX(p.LastActivityDate)                       AS LastPostActivity,
        MAX(c.CreationDate)                           AS LastCommentDate,
        GREATEST(
            COALESCE(MAX(p.LastActivityDate), TIMESTAMP '1970-01-01'),
            COALESCE(MAX(c.CreationDate),      TIMESTAMP '1970-01-01')
        )                                             AS MostRecentActivity
    FROM Users u
    LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId      = u.Id
    GROUP BY u.Id
),

/* ------------------------------------------------------------------
   3.  Top scoring post per user (question or answer)
------------------------------------------------------------------- */
TopPostPerUser AS (
    SELECT
        p.OwnerUserId,
        p.Id                AS PostId,
        p.Title,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST) AS rn
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)            -- questions and answers only
      AND p.OwnerUserId IS NOT NULL
),

/* ------------------------------------------------------------------
   4.  Tag usage statistics (counts, averages, ranking)
------------------------------------------------------------------- */
TagStats AS (
    SELECT
        t.TagName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId=1)                AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId=2)                AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId=1)               AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId=2)               AS AvgAnswerScore,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC)           AS TagRank
    FROM Tags t
    LEFT JOIN Posts p
        ON p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY t.TagName
),

/* ------------------------------------------------------------------
   5.  Assemble per‑user rows (including correlated sub‑queries for recent activity)
------------------------------------------------------------------- */
UserRows AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.NetVotes,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.RepRank,
        ra.LastPostActivity,
        ra.LastCommentDate,
        ra.MostRecentActivity,
        tp.Title                                   AS RecentTopQuestion,
        tp.Score                                   AS RecentTopScore,
        (SELECT COUNT(*) FROM Posts p2
         WHERE p2.OwnerUserId = us.Id
           AND p2.PostTypeId = 1
           AND p2.CreationDate >= CURRENT_DATE - INTERVAL '30 days') AS QuestionsLast30d,
        (SELECT COUNT(*) FROM Posts p2
         WHERE p2.OwnerUserId = us.Id
           AND p2.PostTypeId = 2
           AND p2.CreationDate >= CURRENT_DATE - INTERVAL '30 days') AS AnswersLast30d,
        CASE
            WHEN us.Reputation > 20000               THEN 'PowerUser'
            WHEN us.Reputation BETWEEN 10000 AND 20000 THEN 'HighRep'
            ELSE                                         'Regular'
        END                                        AS UserTier,
        NULL::varchar(35)   AS TagName,
        NULL::int           AS QuestionCount,
        NULL::int           AS AnswerCount,
        NULL::numeric(10,2) AS AvgQuestionScore,
        NULL::numeric(10,2) AS AvgAnswerScore,
        NULL::int           AS TagRank,
        NULL::varchar(10)   AS TagCategory
    FROM UserStats us
    LEFT JOIN RecentActivity ra   ON ra.Id = us.Id
    LEFT JOIN TopPostPerUser tp   ON tp.OwnerUserId = us.Id AND tp.rn = 1
    WHERE us.RepRank <= 100                     -- limit to top‑100 users
      AND (us.GoldBadges > 0 OR us.SilverBadges > 5)
      AND (us.Reputation > 5000)                -- drop pure “Regular” tier
),

/* ------------------------------------------------------------------
   6.  Assemble tag rows (padding user‑specific columns with NULLs)
------------------------------------------------------------------- */
TagRows AS (
    SELECT
        NULL::int           AS Id,
        NULL::varchar(40)  AS DisplayName,
        NULL::int           AS Reputation,
        NULL::int           AS NetVotes,
        NULL::int           AS GoldBadges,
        NULL::int           AS SilverBadges,
        NULL::int           AS BronzeBadges,
        NULL::int           AS RepRank,
        NULL::timestamp     AS LastPostActivity,
        NULL::timestamp     AS LastCommentDate,
        NULL::timestamp     AS MostRecentActivity,
        NULL::varchar(300)  AS RecentTopQuestion,
        NULL::int           AS RecentTopScore,
        NULL::int           AS QuestionsLast30d,
        NULL::int           AS AnswersLast30d,
        NULL::varchar(10)   AS UserTier,
        ts.TagName,
        ts.QuestionCount,
        ts.AnswerCount,
        ROUND(ts.AvgQuestionScore,2) AS AvgQuestionScore,
        ROUND(ts.AvgAnswerScore,2)   AS AvgAnswerScore,
        ts.TagRank,
        CASE WHEN ts.TagRank <= 10 THEN 'TopTag' ELSE 'Tag' END AS TagCategory
    FROM TagStats ts
    WHERE ts.TagRank <= 20
)

/* ------------------------------------------------------------------
   7.  Final result: UNION ALL of user rows and tag rows
------------------------------------------------------------------- */
SELECT *
FROM UserRows
UNION ALL
SELECT *
FROM TagRows
ORDER BY
    RepRank NULLS LAST,          -- users first, ordered by rank
    TagRank  NULLS LAST;         -- then tags ordered by rank
