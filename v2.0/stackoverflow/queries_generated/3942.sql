-- {"query": "3942.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3112} 

WITH
/*-------------------------------------------------
  1. Reputation and badge aggregates per user
---------------------------------------------------*/
UserReputation AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)               AS NetVotes,
        COUNT(b.Id) FILTER (WHERE b.Class = 1)                        AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2)                        AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3)                        AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate,
             u.UpVotes, u.DownVotes
),

/*-------------------------------------------------
  2. Activity counts (questions / answers) per user
---------------------------------------------------*/
UserActivity AS (
    SELECT
        p.OwnerUserId                                    AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)        AS QuestionsAsked,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)        AS AnswersGiven,
        MAX(p.CreationDate)                             AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

/*-------------------------------------------------
  3. Tag popularity (used later for window ranking)
---------------------------------------------------*/
TagPopularity AS (
    SELECT
        t.TagName,
        t.Count,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC)      AS TagRank
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
),

/*-------------------------------------------------
  4. Flatten question tags and count per user/tag
---------------------------------------------------*/
UserQuestionTags AS (
    SELECT
        p.OwnerUserId                                                AS UserId,
        UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2),
                               '><'))                               AS Tag,
        COUNT(*)                                                     AS TagUsage
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, Tag
),

/*-------------------------------------------------
  5. Top‑N tag per user (window function)
---------------------------------------------------*/
TopUserTags AS (
    SELECT
        uq.UserId,
        uq.Tag,
        uq.TagUsage,
        ROW_NUMBER() OVER (PARTITION BY uq.UserId ORDER BY uq.TagUsage DESC) AS TagPos
    FROM UserQuestionTags uq
),

/*-------------------------------------------------
  6. Most recent close‑reason per post (correlated subquery)
---------------------------------------------------*/
RecentCloseReasons AS (
    SELECT
        ph.PostId,
        ph.CreationDate,
        CAST(ph.Comment AS int)                           AS CloseReasonId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10          -- Close
),

/*-------------------------------------------------
  7. Close‑reason aggregates per user
---------------------------------------------------*/
UserCloseStats AS (
    SELECT
        p.OwnerUserId                                          AS UserId,
        COUNT(DISTINCT rc.CloseReasonId)                       AS DistinctCloseReasons,
        COUNT(*) FILTER (WHERE rc.CloseReasonId = 101)         AS DuplicateClosings,
        COUNT(*) FILTER (WHERE rc.CloseReasonId = 102)         AS OffTopicClosings
    FROM Posts p
    JOIN RecentCloseReasons rc ON rc.PostId = p.Id AND rc.rn = 1
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

/*-------------------------------------------------
  8. Combine everything and compute a composite score
---------------------------------------------------*/
Combined AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        ur.NetVotes,
        ur.GoldBadges,
        ur.SilverBadges,
        ur.BronzeBadges,
        COALESCE(ua.QuestionsAsked,0)               AS QuestionsAsked,
        COALESCE(ua.AnswersGiven,0)                 AS AnswersGiven,
        COALESCE(ua.LastPostDate, u.CreationDate)   AS LastActivity,
        COALESCE(ucs.DistinctCloseReasons,0)        AS DistinctCloseReasons,
        COALESCE(ucs.DuplicateClosings,0)           AS DuplicateClosings,
        COALESCE(ucs.OffTopicClosings,0)            AS OffTopicClosings,
        /* CompositeScore blends reputation, votes, badges, activity & penalties */
        (u.Reputation * 0.4) +
        (ur.NetVotes * 0.3) +
        (ur.GoldBadges   * 100) +
        (ur.SilverBadges * 50)  +
        (ur.BronzeBadges * 20)  +
        (COALESCE(ua.QuestionsAsked,0) * 5) +
        (COALESCE(ua.AnswersGiven,0)   * 8) -
        (COALESCE(ucs.DistinctCloseReasons,0) * 15)         AS CompositeScore
    FROM Users u
    LEFT JOIN UserReputation ur   ON ur.Id = u.Id
    LEFT JOIN UserActivity   ua   ON ua.UserId = u.Id
    LEFT JOIN UserCloseStats ucs  ON ucs.UserId = u.Id
)

/*=================================================
  FINAL RESULT: Top‑10 users by CompositeScore,
  enriched with tier, top tag and NULL handling.
===================================================*/
SELECT *
FROM (
    SELECT
        c.*,
        ROW_NUMBER() OVER (ORDER BY c.CompositeScore DESC)         AS RankOverall,
        CASE
            WHEN c.GoldBadges > 0                     THEN 'Elite'
            WHEN c.SilverBadges > 5                   THEN 'Veteran'
            ELSE                                           'Member'
        END                                                         AS UserTier,
        /* Top tag (if any) for the user */
        (SELECT tq.Tag
         FROM TopUserTags tq
         WHERE tq.UserId = c.Id AND tq.TagPos = 1)                 AS TopTag,
        /* Demonstrate NULL‑logic: return NULL when no duplicate closings */
        COALESCE(NULLIF(c.DuplicateClosings,0), NULL)               AS FirstDuplicateClosing
    FROM Combined c
) ranked
WHERE RankOverall <= 10

/*-------------------------------------------------
  Add a dummy row using UNION ALL + EXCEPT to stress set ops
---------------------------------------------------*/
UNION ALL
SELECT
    NULL::int                     AS Id,
    '---'                         AS DisplayName,
    NULL::int                     AS Reputation,
    NULL::int                     AS NetVotes,
    NULL::int                     AS GoldBadges,
    NULL::int                     AS SilverBadges,
    NULL::int                     AS BronzeBadges,
    NULL::int                     AS QuestionsAsked,
    NULL::int                     AS AnswersGiven,
    NULL::timestamp               AS LastActivity,
    NULL::int                     AS DistinctCloseReasons,
    NULL::int                     AS DuplicateClosings,
    NULL::int                     AS OffTopicClosings,
    NULL::numeric                 AS CompositeScore,
    NULL::int                     AS RankOverall,
    NULL::varchar                 AS UserTier,
    NULL::varchar                 AS TopTag,
    NULL::timestamp               AS FirstDuplicateClosing
WHERE FALSE
EXCEPT
SELECT *
FROM (
    SELECT *
    FROM ranked
    WHERE UserTier = 'Member' AND CompositeScore < 0
) sub;
