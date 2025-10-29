-- {"query": "3940.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2912}
WITH
UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS NetVotes,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
),

RecentActivity AS (
    SELECT
        u.Id,
        MAX(p.LastActivityDate) AS LastPostActivity,
        MAX(c.CreationDate) AS LastCommentDate,
        GREATEST(
            COALESCE(MAX(p.LastActivityDate), CAST('1970-01-01' AS timestamp)),
            COALESCE(MAX(c.CreationDate), CAST('1970-01-01' AS timestamp))
        ) AS MostRecentActivity
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id
),

TopPostPerUser AS (
    SELECT
        p.OwnerUserId,
        p.Id AS PostId,
        p.Title,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST) AS rn
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
      AND p.OwnerUserId IS NOT NULL
),

TagStats AS (
    SELECT
        t.TagName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Tags t
    LEFT JOIN Posts p
        ON p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY t.TagName
),

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
        tp.Title AS RecentTopQuestion,
        tp.Score AS RecentTopScore,
        (SELECT COUNT(*) FROM Posts p2
         WHERE p2.OwnerUserId = us.Id
           AND p2.PostTypeId = 1
           AND p2.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days') AS QuestionsLast30d,
        (SELECT COUNT(*) FROM Posts p2
         WHERE p2.OwnerUserId = us.Id
           AND p2.PostTypeId = 2
           AND p2.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days') AS AnswersLast30d,
        CASE
            WHEN us.Reputation > 20000 THEN 'PowerUser'
            WHEN us.Reputation BETWEEN 10000 AND 20000 THEN 'HighRep'
            ELSE 'Regular'
        END AS UserTier,
        CAST(NULL AS varchar(35)) AS TagName,
        CAST(NULL AS int) AS QuestionCount,
        CAST(NULL AS int) AS AnswerCount,
        CAST(NULL AS numeric(10,2)) AS AvgQuestionScore,
        CAST(NULL AS numeric(10,2)) AS AvgAnswerScore,
        CAST(NULL AS int) AS TagRank,
        CAST(NULL AS varchar(10)) AS TagCategory
    FROM UserStats us
    LEFT JOIN RecentActivity ra ON ra.Id = us.Id
    LEFT JOIN TopPostPerUser tp ON tp.OwnerUserId = us.Id AND tp.rn = 1
    WHERE us.RepRank <= 100
      AND (us.GoldBadges > 0 OR us.SilverBadges > 5)
      AND (us.Reputation > 5000)
),

TagRows AS (
    SELECT
        CAST(NULL AS int) AS Id,
        CAST(NULL AS varchar(40)) AS DisplayName,
        CAST(NULL AS int) AS Reputation,
        CAST(NULL AS int) AS NetVotes,
        CAST(NULL AS int) AS GoldBadges,
        CAST(NULL AS int) AS SilverBadges,
        CAST(NULL AS int) AS BronzeBadges,
        CAST(NULL AS int) AS RepRank,
        CAST(NULL AS timestamp) AS LastPostActivity,
        CAST(NULL AS timestamp) AS LastCommentDate,
        CAST(NULL AS timestamp) AS MostRecentActivity,
        CAST(NULL AS varchar(300)) AS RecentTopQuestion,
        CAST(NULL AS int) AS RecentTopScore,
        CAST(NULL AS int) AS QuestionsLast30d,
        CAST(NULL AS int) AS AnswersLast30d,
        CAST(NULL AS varchar(10)) AS UserTier,
        ts.TagName,
        ts.QuestionCount,
        ts.AnswerCount,
        ROUND(ts.AvgQuestionScore,2) AS AvgQuestionScore,
        ROUND(ts.AvgAnswerScore,2) AS AvgAnswerScore,
        ts.TagRank,
        CASE WHEN ts.TagRank <= 10 THEN 'TopTag' ELSE 'Tag' END AS TagCategory
    FROM TagStats ts
    WHERE ts.TagRank <= 20
)

SELECT *
FROM UserRows
UNION ALL
SELECT *
FROM TagRows
ORDER BY
    RepRank NULLS LAST,
    TagRank NULLS LAST;