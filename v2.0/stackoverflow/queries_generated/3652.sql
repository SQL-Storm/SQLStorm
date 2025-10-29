-- {"query": "3652.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2035} 

/*  Complex performance‑benchmark query using the StackOverflow schema  */
WITH 
/*--------------------------------------------------------------
  1) Basic per‑user aggregates (uses correlated sub‑queries)
--------------------------------------------------------------*/
UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location,'<unknown>')               AS Location,
        (
            SELECT COUNT(*) 
            FROM Posts p 
            WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1   -- questions
        )                                             AS QuestionCount,
        (
            SELECT COUNT(*) 
            FROM Posts p 
            WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2   -- answers
        )                                             AS AnswerCount,
        (
            SELECT COUNT(*) 
            FROM Comments c 
            WHERE c.UserId = u.Id
        )                                             AS CommentCount,
        (
            SELECT COUNT(*) 
            FROM Badges b 
            WHERE b.UserId = u.Id
        )                                             AS BadgeCount,
        (
            SELECT MAX(p.CreationDate) 
            FROM Posts p 
            WHERE p.OwnerUserId = u.Id
        )                                             AS LastPostDate
    FROM Users u
),

/*--------------------------------------------------------------
  2) Global tag ranking (window function)
--------------------------------------------------------------*/
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
),

/*--------------------------------------------------------------
  3) Latest post per user (window function + outer join)
--------------------------------------------------------------*/
UserRecentPosts AS (
    SELECT 
        p.OwnerUserId,
        p.Id        AS PostId,
        p.Title,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId 
                           ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),

/*--------------------------------------------------------------
  4) Extract tags from posts, rank them per user (correlated, set)
--------------------------------------------------------------*/
UserTagInfo AS (
    SELECT 
        pt.OwnerUserId,
        pt.TagName,
        ROW_NUMBER() OVER (PARTITION BY pt.OwnerUserId 
                           ORDER BY tt.Count DESC) AS rn
    FROM (
        SELECT 
            p.OwnerUserId,
            UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS TagName
        FROM Posts p
        WHERE p.Tags IS NOT NULL
    ) pt
    JOIN Tags tt ON tt.TagName = pt.TagName
),

/*--------------------------------------------------------------
  5) Combined per‑user view with all previous CTEs
--------------------------------------------------------------*/
Combined AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.Location,
        us.QuestionCount,
        us.AnswerCount,
        us.CommentCount,
        us.BadgeCount,
        us.LastPostDate,
        COALESCE(urp.Title,'<no recent post>')            AS RecentPostTitle,
        COALESCE(urp.Score,0)                            AS RecentPostScore,
        CASE 
            WHEN us.Reputation > 20000 THEN 'Elite'
            WHEN us.Reputation > 5000  THEN 'Power'
            ELSE                           'Regular'
        END                                              AS ReputationTier,
        STRING_AGG(DISTINCT uti.TagName, ', ') 
            FILTER (WHERE uti.rn <= 5)                  AS Top5Tags
    FROM UserStats us
    LEFT JOIN UserRecentPosts urp 
        ON urp.OwnerUserId = us.Id AND urp.rn = 1
    LEFT JOIN UserTagInfo uti 
        ON uti.OwnerUserId = us.Id
    GROUP BY 
        us.Id, us.DisplayName, us.Reputation, us.Location,
        us.QuestionCount, us.AnswerCount, us.CommentCount,
        us.BadgeCount, us.LastPostDate,
        urp.Title, urp.Score
    HAVING COUNT(uti.TagName) FILTER (WHERE uti.rn <= 5) > 0
)

/*================================================================
  Final result set: top 100 users + an aggregate summary row
================================================================*/
SELECT 
    c.Id,
    c.DisplayName,
    c.Reputation,
    c.Location,
    c.QuestionCount,
    c.AnswerCount,
    c.CommentCount,
    c.BadgeCount,
    c.LastPostDate,
    c.RecentPostTitle,
    c.RecentPostScore,
    c.ReputationTier,
    c.Top5Tags
FROM Combined c
ORDER BY c.Reputation DESC
LIMIT 100

UNION ALL

SELECT 
    NULL                     AS Id,
    'Aggregate Summary'      AS DisplayName,
    NULL                     AS Reputation,
    NULL                     AS Location,
    SUM(QuestionCount)       AS QuestionCount,
    SUM(AnswerCount)         AS AnswerCount,
    SUM(CommentCount)        AS CommentCount,
    SUM(BadgeCount)          AS BadgeCount,
    NULL                     AS LastPostDate,
    NULL                     AS RecentPostTitle,
    NULL                     AS RecentPostScore,
    NULL                     AS ReputationTier,
    NULL                     AS Top5Tags
FROM Combined;
