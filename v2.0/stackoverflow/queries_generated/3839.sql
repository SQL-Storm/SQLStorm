-- {"query": "3839.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1046} 

WITH RECURSIVE TagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        CAST(t.TagName AS VARCHAR(4000)) AS Path,
        1 AS Depth
    FROM Tags t
    WHERE t.IsModeratorOnly = 0

    UNION ALL

    SELECT
        t.Id,
        t.TagName,
        CONCAT(p.Path, '>', t.TagName),
        p.Depth + 1
    FROM Tags t
    JOIN TagHierarchy p ON POSITION('>' || t.TagName || '<' IN '<' || p.TagName || '>') > 0
    WHERE t.IsModeratorOnly = 0
),
UserStats AS (
    SELECT
        u.Id                                           AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id)                           AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)   AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)   AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)   AS BronzeBadges,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END)   AS AvgQuestionScore,
        MAX(p.CreationDate)                               AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b          ON b.UserId = u.Id
    LEFT JOIN Posts p           ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopActiveUsers AS (
    SELECT
        us.*,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.GoldBadges DESC, us.AvgQuestionScore DESC) AS rn
    FROM UserStats us
    WHERE us.QuestionCount > 0
),
UserRecentPosts AS (
    SELECT
        p.OwnerUserId                AS UserId,
        p.Id                         AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.QuestionCount,
    tu.AnswerCount,
    ROUND(tu.AvgQuestionScore::numeric, 2)          AS AvgQuestionScore,
    TO_CHAR(tu.LastPostDate, 'YYYY-MM-DD')          AS LastPostDate,
    urp.PostId,
    urp.Title,
    urp.Score                                      AS RecentPostScore,
    COALESCE(tg.Path, '<no-tag>')                  AS TagPath,
    CASE
        WHEN tu.Reputation > 20000 AND tu.GoldBadges >= 10 THEN 'Elite'
        WHEN tu.Reputation > 10000 THEN 'Veteran'
        WHEN tu.Reputation > 5000  THEN 'Experienced'
        ELSE 'Rising'
    END                                            AS ReputationTier,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM Votes v
            WHERE v.PostId = urp.PostId
              AND v.VoteTypeId = 2
              AND v.UserId = tu.UserId
        ) THEN 1
        ELSE 0
    END                                            AS HasUpvotedOwnRecentPost
FROM TopActiveUsers tu
LEFT JOIN UserRecentPosts urp
       ON urp.UserId = tu.UserId AND urp.rn = 1
LEFT JOIN LATERAL (
    SELECT
        th.Path
    FROM TagHierarchy th
    WHERE POSITION('<' || REGEXP_REPLACE(urp.Title, '\s+', '') || '>' IN th.Path) > 0
    ORDER BY th.Depth DESC
    LIMIT 1
) tg ON TRUE
WHERE tu.rn <= 100
ORDER BY tu.rn;
