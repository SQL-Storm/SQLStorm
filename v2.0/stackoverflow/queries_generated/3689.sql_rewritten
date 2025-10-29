-- {"query": "3689.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2092} 
WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           u.CreationDate,
           u.LastAccessDate,
           COALESCE(p.PostCnt,0)                AS PostCount,
           COALESCE(a.AnswerCnt,0)              AS AnswerCount,
           COALESCE(a.QuestionCnt,0)            AS QuestionCount,
           COALESCE(b.BadgeCnt,0)               AS BadgeCount,
           COALESCE(v.VoteScore,0)              AS VoteScore,
           ROW_NUMBER() OVER (PARTITION BY u.Id
                              ORDER BY p.LastPostDate DESC NULLS LAST) AS rn
    FROM Users u
    LEFT JOIN (
        SELECT OwnerUserId,
               COUNT(*)                         AS PostCnt,
               MAX(CreationDate)                AS LastPostDate
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
        GROUP BY OwnerUserId
    ) p  ON u.Id = p.OwnerUserId
    LEFT JOIN (
        SELECT OwnerUserId,
               SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCnt,
               SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCnt
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
        GROUP BY OwnerUserId
    ) a  ON u.Id = a.OwnerUserId
    LEFT JOIN (
        SELECT UserId,
               COUNT(*)                         AS BadgeCnt
        FROM Badges
        GROUP BY UserId
    ) b  ON u.Id = b.UserId
    LEFT JOIN (
        SELECT p.OwnerUserId,
               COALESCE(SUM(CASE vt.Id
                              WHEN 2 THEN 1      /* UpMod   */
                              WHEN 3 THEN -1     /* DownMod */
                              ELSE 0 END),0)    AS VoteScore
        FROM Votes v
        JOIN VoteTypes vt      ON v.VoteTypeId = vt.Id
        JOIN Posts p           ON v.PostId = p.Id
        GROUP BY p.OwnerUserId
    ) v  ON u.Id = v.OwnerUserId
),

TagPopularity AS (
    SELECT t.TagName,
           COUNT(*)                                 AS UsageCnt,
           ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS TagRank
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT trim(both '<>' FROM unnest(string_to_array(p.Tags, '><'))) AS tag
    ) tg
    JOIN Tags t ON tg.tag = t.TagName
    WHERE p.PostTypeId = 1               /* only questions */
    GROUP BY t.TagName
),

TopTagPerUser AS (
    SELECT us.Id,
           tp.TagName,
           tp.UsageCnt
    FROM UserStats us
    LEFT JOIN LATERAL (
        SELECT t.TagName,
               t.UsageCnt
        FROM TagPopularity t
        ORDER BY t.UsageCnt DESC
        LIMIT 1
    ) tp ON true
    WHERE us.rn = 1
),

RecentComments AS (
    SELECT us.Id,
           COUNT(c.Id) AS RecentCommentCnt
    FROM UserStats us
    LEFT JOIN Comments c
           ON c.UserId = us.Id
          AND c.CreationDate >= us.LastAccessDate - INTERVAL '30 days'
    WHERE us.rn = 1
    GROUP BY us.Id
)

SELECT us.Id,
       us.DisplayName,
       us.Reputation,
       us.PostCount,
       us.AnswerCount,
       us.QuestionCount,
       us.BadgeCount,
       us.VoteScore,
       CASE
           WHEN us.Reputation >= 20000 THEN 'Legendary'
           WHEN us.Reputation >= 10000 THEN 'Expert'
           WHEN us.Reputation >= 5000  THEN 'Advanced'
           WHEN us.Reputation >= 1000  THEN 'Intermediate'
           ELSE 'Novice'
       END                                         AS ReputationTier,
       COALESCE(tp.TagName, 'NoTag')               AS TopTag,
       COALESCE(tp.UsageCnt,0)                     AS TopTagUsage,
       COALESCE(rc.RecentCommentCnt,0)             AS RecentCommentCount
FROM UserStats us
LEFT JOIN TopTagPerUser tp ON us.Id = tp.Id
LEFT JOIN RecentComments rc ON us.Id = rc.Id
WHERE us.rn = 1

UNION ALL

/*  Global aggregates row  */
SELECT NULL,
       'Aggregates',
       SUM(us.Reputation)      AS TotalReputation,
       SUM(us.PostCount)       AS TotalPosts,
       SUM(us.AnswerCount)     AS TotalAnswers,
       SUM(us.QuestionCount)   AS TotalQuestions,
       SUM(us.BadgeCount)      AS TotalBadges,
       SUM(us.VoteScore)       AS TotalVoteScore,
       NULL,
       NULL,
       NULL,
       NULL
FROM UserStats us
WHERE us.Reputation IS NOT NULL;