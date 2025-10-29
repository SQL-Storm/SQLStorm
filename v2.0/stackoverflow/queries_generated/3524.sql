-- {"query": "3524.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2453} 

/*  Complex benchmark query for the StackOverflow schema  */
WITH
/*--------------------------------------------------------------
  User‑level aggregates (questions, answers, scores, recent post)
----------------------------------------------------------------*/
UserStats AS (
    SELECT
        u.Id                                   AS UserId,
        COALESCE(u.DisplayName, 'Anonymous')   AS DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown')        AS Location,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)               AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)               AS AnswerCount,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 1)              AS QuestionScoreSum,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2)              AS AnswerScoreSum,
        MAX(p.CreationDate)                                     AS LastPostDate,
        /* Correlated sub‑query: distinct tag count for this user */
        (SELECT COUNT(DISTINCT t)
         FROM (
                 SELECT UNNEST(STRING_TO_ARRAY(
                     REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ','
                 )) AS t
                 FROM Posts p
                 WHERE p.OwnerUserId = u.Id AND p.Tags IS NOT NULL
              ) sub
        )                                          AS DistinctTagCount
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),

/*--------------------------------------------------------------
  Badge aggregates and ranking per user
----------------------------------------------------------------*/
BadgeRanks AS (
    SELECT
        b.UserId,
        COUNT(*)                                          AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)      AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)      AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)      AS BronzeBadges,
        ROW_NUMBER() OVER (PARTITION BY b.UserId
                           ORDER BY b.Date DESC)          AS RecentBadgeRank
    FROM Badges b
    GROUP BY b.UserId
),

/*--------------------------------------------------------------
  Recent votes (last 30 days) per post, with row_number()
----------------------------------------------------------------*/
RecentVotes AS (
    SELECT
        v.PostId,
        v.VoteTypeId,
        v.UserId,
        v.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY v.PostId
                           ORDER BY v.CreationDate DESC) AS rn
    FROM Votes v
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),

/*--------------------------------------------------------------
  Top‑scoring questions from the past year (global ranking)
----------------------------------------------------------------*/
TopQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        COALESCE(p.Tags, '')                              AS Tags,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS Rank
    FROM Posts p
    WHERE p.PostTypeId = 1                                   -- only questions
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
),

/*--------------------------------------------------------------
  Tag‑level aggregates for a given question (set operator demo)
----------------------------------------------------------------*/
QuestionTagInfo AS (
    SELECT
        tq.Id           AS QuestionId,
        STRING_AGG(DISTINCT tg.TagName, ', ') AS TagList,
        COUNT(tg.Id)    AS TagCount
    FROM TopQuestions tq
    LEFT JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(
                REPLACE(REPLACE(tq.Tags, '<', ''), '>', ''), ','
        )) AS Tag
    ) AS raw(tag) ON TRUE
    LEFT JOIN Tags tg ON tg.TagName = raw.Tag
    GROUP BY tq.Id
)

/*================================================================
  Final combined result set (outer joins, window functions, CASE,
  COALESCE, string handling, NULL logic, UNION ALL)
================================================================*/
SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.Location,
    us.QuestionCount,
    us.AnswerCount,
    us.QuestionScoreSum,
    us.AnswerScoreSum,
    us.DistinctTagCount,
    br.TotalBadges,
    br.GoldBadges,
    br.SilverBadges,
    br.BronzeBadges,
    CASE
        WHEN br.GoldBadges > 0 THEN 'Elite'
        WHEN br.SilverBadges > 0 THEN 'Pro'
        ELSE 'Member'
    END                                     AS UserTier,
    tq.Id                                 AS TopQuestionId,
    tq.Title                              AS TopQuestionTitle,
    tq.Score                              AS TopQuestionScore,
    tq.ViewCount                          AS TopQuestionViews,
    qti.TagList                           AS TopQuestionTags,
    qti.TagCount                          AS TopQuestionTagCount,
    rv.VoteTypeId,
    rv.CreationDate                       AS RecentVoteDate,
    COALESCE(vu.DisplayName, 'Anonymous') AS VoterDisplayName
FROM UserStats us
LEFT JOIN BadgeRanks br               ON br.UserId = us.UserId
LEFT JOIN TopQuestions tq            ON tq.Rank = 1 AND tq.OwnerUserId = us.UserId
LEFT JOIN QuestionTagInfo qti        ON qti.QuestionId = tq.Id
LEFT JOIN RecentVotes rv             ON rv.PostId = tq.Id AND rv.rn = 1
LEFT JOIN Users vu                    ON vu.Id = rv.UserId
WHERE us.Reputation > 1000
  AND (us.QuestionCount + us.AnswerCount) > 10

UNION ALL

/* Dummy row to force a UNION ALL operator (helps benchmark set ops) */
SELECT
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL
WHERE FALSE;
