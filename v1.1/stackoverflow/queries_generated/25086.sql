-- {"query": "25086.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2625} 

/*  Performance‑benchmarking query – uses CTEs, window functions, outer joins,
    correlated sub‑queries, set operators, complex predicates, string handling
    and NULL logic.  */
WITH 
/*---------------------------------------------------------------------------
  User‑level aggregates (badges, posts, answers) – uses correlated sub‑queries.
---------------------------------------------------------------------------*/
UserAgg AS (
    SELECT 
        u.Id                                 AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate                       AS UserCreated,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCnt,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCnt
    FROM Users u
    WHERE u.Reputation >= 500
),

/*---------------------------------------------------------------------------
  Recent activity per user (last post date, last up‑vote date) – outer joins.
---------------------------------------------------------------------------*/
RecentActivity AS (
    SELECT 
        p.OwnerUserId                            AS UserId,
        MAX(p.CreationDate)                     AS LastPostDate,
        MAX(v.CreationDate) FILTER (WHERE v.VoteTypeId = 2) AS LastUpVoteDate
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
),

/*---------------------------------------------------------------------------
  Tag statistics – window function for ranking tags by usage.
---------------------------------------------------------------------------*/
TagStats AS (
    SELECT 
        t.TagName,
        COUNT(p.Id)                             AS TagPostCnt,
        SUM(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END) AS TagScoreSum,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
                 AND p.PostTypeId = 1               -- only questions
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 20
),

/*---------------------------------------------------------------------------
  Post‑level ranking – window function over vote totals.
---------------------------------------------------------------------------*/
PostRank AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        COALESCE(p.Score * LOG(1 + p.ViewCount), 0) AS CompositeScore,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY 
                     COALESCE(p.Score * LOG(1 + p.ViewCount), 0) DESC) AS ScoreRank
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)                      -- questions & answers
),

/*---------------------------------------------------------------------------
  Users with “high‑impact” activity – join the previous CTEs, use CASE & NULL logic.
---------------------------------------------------------------------------*/
HighImpactUsers AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.QuestionCnt,
        ua.AnswerCnt,
        COALESCE(ra.LastPostDate, '1970-01-01')      AS LastPostDate,
        COALESCE(ra.LastUpVoteDate, '1970-01-01')   AS LastUpVoteDate,
        CASE 
            WHEN ua.Reputation >= 10000 THEN 'Legendary'
            WHEN ua.Reputation BETWEEN 5000 AND 9999 THEN 'Power'
            WHEN ua.Reputation BETWEEN 2000 AND 4999 THEN 'Experienced'
            ELSE 'Rising'
        END                                          AS ReputationTier,
        /* top 3 tags for this user – string aggregation */
        (SELECT STRING_AGG(t.TagName, ', ') 
         FROM Tags t
         JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
         WHERE p.OwnerUserId = ua.UserId
         GROUP BY t.TagName
         ORDER BY COUNT(*) DESC
         LIMIT 3)                                 AS Top3Tags,
        /* flag for users who have ever been closed (via PostHistory) */
        EXISTS (SELECT 1 
                FROM PostHistory ph 
                WHERE ph.UserId = ua.UserId 
                  AND ph.PostHistoryTypeId = 10)    AS EverClosedFlag
    FROM UserAgg ua
    LEFT JOIN RecentActivity ra ON ra.UserId = ua.UserId
    WHERE (ua.GoldBadges + ua.SilverBadges + ua.BronzeBadges) >= 3
),

/*---------------------------------------------------------------------------
  Union of high‑impact users and a “new‑comer” set (set operator).
---------------------------------------------------------------------------*/
CombinedUsers AS (
    SELECT *
    FROM HighImpactUsers
    UNION ALL
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        0,0,0,
        0,0,
        NULL,NULL,
        'Newcomer'          AS ReputationTier,
        NULL                AS Top3Tags,
        FALSE               AS EverClosedFlag
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE b.Id IS NULL                         -- users without any badge
      AND u.Reputation < 200
)

SELECT 
    cu.UserId,
    cu.DisplayName,
    cu.Reputation,
    cu.GoldBadges,
    cu.SilverBadges,
    cu.BronzeBadges,
    cu.QuestionCnt,
    cu.AnswerCnt,
    cu.LastPostDate,
    cu.LastUpVoteDate,
    cu.ReputationTier,
    cu.Top3Tags,
    cu.EverClosedFlag,
    ts.TagName               AS PopularTag,
    ts.TagPostCnt            AS TagPostCount,
    ts.TagScoreSum           AS TagScoreTotal,
    pr.Title                 AS TopScoringPost,
    pr.CompositeScore,
    pr.ScoreRank
FROM CombinedUsers cu
LEFT JOIN TagStats ts               ON ts.TagRank = 1                -- most used tag overall
LEFT JOIN PostRank pr               ON pr.ScoreRank = 1
ORDER BY 
    CASE cu.ReputationTier 
        WHEN 'Legendary'   THEN 1
        WHEN 'Power'       THEN 2
        WHEN 'Experienced' THEN 3
        WHEN 'Rising'      THEN 4
        ELSE 5
    END,
    cu.GoldBadges DESC,
    cu.AnswerCnt DESC
OFFSET 0 ROWS FETCH NEXT 200 ROWS ONLY;
