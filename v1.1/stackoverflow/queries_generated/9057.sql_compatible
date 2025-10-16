WITH RecentPosts AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        LENGTH(p.Body) - LENGTH(REPLACE(p.Body, '<code>', '')) AS CodeTagCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
TopActiveUsers AS (
    SELECT 
        u.Id            AS UserId,
        u.DisplayName,
        u.Reputation,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(rp.CodeTagCount)                          AS TotalCodeSnippets,
        RANK() OVER (ORDER BY SUM(rp.CodeTagCount) DESC) AS CodeRank
    FROM Users u
    LEFT JOIN RecentPosts rp
      ON u.Id = rp.OwnerUserId
     AND rp.rn <= 5
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagUsage AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS UsageCount
    FROM Tags t
    LEFT JOIN Posts p
      ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    GROUP BY t.TagName
),
UnionCounts AS (
    SELECT 'High' AS Tier, COUNT(*) AS UserCount
    FROM TopActiveUsers
    WHERE AnswerCount > QuestionCount
    UNION ALL
    SELECT 'Low'  AS Tier, COUNT(*) AS UserCount
    FROM TopActiveUsers
    WHERE AnswerCount <= QuestionCount
),
Aggregated AS (
    SELECT
        TAU.UserId,
        TAU.DisplayName,
        TAU.Reputation,
        TAU.QuestionCount,
        TAU.AnswerCount,
        TAU.TotalCodeSnippets,
        TAU.CodeRank,
        TU.UsageCount,
        COALESCE(
          (SELECT COUNT(1)
           FROM Badges b
           WHERE b.UserId = TAU.UserId
             AND b.Class = 1), 
          0
        ) AS GoldBadgeCount,
        CASE
            WHEN TAU.Reputation > 10000 THEN 'Veteran'
            WHEN TAU.Reputation > 1000  THEN 'Experienced'
            ELSE 'Newbie'
        END AS ExperienceLevel,
        (
          SELECT
                 SUBSTRING(p2.Tags FROM 2 FOR (POSITION('><' IN (p2.Tags || '><')) - 2))
          FROM Posts p2
          WHERE p2.OwnerUserId = TAU.UserId
            AND p2.Tags IS NOT NULL
          ORDER BY p2.CreationDate DESC
          LIMIT 1
        ) AS FavoriteTag
    FROM TopActiveUsers TAU
    LEFT JOIN TagUsage TU
      ON TU.TagName = (
          SELECT
                 SUBSTRING(p2.Tags FROM 2 FOR (POSITION('><' IN (p2.Tags || '><')) - 2))
          FROM Posts p2
          WHERE p2.OwnerUserId = TAU.UserId
            AND p2.Tags IS NOT NULL
          ORDER BY p2.CreationDate DESC
          LIMIT 1
      )
    GROUP BY
        TAU.UserId,
        TAU.DisplayName,
        TAU.Reputation,
        TAU.QuestionCount,
        TAU.AnswerCount,
        TAU.TotalCodeSnippets,
        TAU.CodeRank,
        TU.UsageCount
)
SELECT
    A.UserId,
    A.DisplayName,
    A.ExperienceLevel,
    A.Reputation,
    A.QuestionCount,
    A.AnswerCount,
    A.TotalCodeSnippets,
    A.CodeRank,
    A.UsageCount,
    A.GoldBadgeCount,
    A.FavoriteTag,
    CASE
        WHEN A.AnswerCount = 0 THEN NULL
        ELSE CAST(A.QuestionCount AS DECIMAL(9,2))
             / NULLIF(A.AnswerCount, 0)
    END AS QtoARatio,
    U.UserCount        AS TierUserCount,
    (A.DisplayName || ' [' || A.ExperienceLevel || ']') AS Label
FROM Aggregated A
CROSS JOIN UnionCounts U
WHERE A.CodeRank <= 50
  AND (A.UsageCount > 100 OR A.GoldBadgeCount > 0)
ORDER BY A.TotalCodeSnippets DESC,
         A.Reputation DESC;