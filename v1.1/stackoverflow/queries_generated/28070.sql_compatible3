WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Location,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS Upvotes,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS RankInLocation
    FROM Users u
    WHERE u.Reputation > 1000
),
PostAnalysis AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        (LENGTH(p.Body) - LENGTH(REPLACE(p.Body, '<code>', ''))) AS CodeSnippets,
        NULLIF(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags)), '') AS TagsTrimmed,
        (SELECT COUNT(DISTINCT ph.UserId) 
         FROM PostHistory ph 
         WHERE ph.PostId = p.Id 
            AND ph.PostHistoryTypeId IN (2,5,8) 
            AND ph.CreationDate BETWEEN p.CreationDate AND p.CreationDate + INTERVAL '1' YEAR) AS Editors
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate > DATE '2015-01-01'
)
SELECT 
    us.DisplayName,
    us.GoldBadges,
    us.Upvotes,
    pa.Score AS PostScore,
    pa.CodeSnippets,
    pa.Editors,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pa.Id) AS CommentCount,
    (SELECT AVG(CAST(p2.AnswerCount AS NUMERIC)) FROM Posts p2 WHERE p2.OwnerUserId = us.Id) AS AvgAnswers,
    (CASE WHEN pa.TagsTrimmed IS NULL THEN NULL
          WHEN pa.TagsTrimmed = '' THEN 0
          ELSE (LENGTH(pa.TagsTrimmed) - LENGTH(REPLACE(pa.TagsTrimmed, '><', '')))/LENGTH('><') + 1
     END) AS TagCount,
    (CASE WHEN pa.TagsTrimmed IS NULL OR pa.TagsTrimmed = '' THEN NULL
          ELSE (
            SELECT STRING_AGG(t.TagName, ', ')
            FROM Tags t
            WHERE EXISTS (
                SELECT 1
                FROM (
                    WITH RECURSIVE split(rest, tag) AS (
                        SELECT pa.TagsTrimmed || '><', NULL
                        UNION ALL
                        SELECT 
                            SUBSTRING(rest FROM POSITION('><' IN rest) + 2),
                            CASE 
                              WHEN POSITION('><' IN rest) > 0 THEN SUBSTRING(rest FROM 1 FOR POSITION('><' IN rest)-1)
                              ELSE NULL
                            END
                        FROM split
                        WHERE POSITION('><' IN rest) > 0
                    )
                    SELECT tag FROM split WHERE tag IS NOT NULL
                ) s
                WHERE s.tag = t.TagName
            ) AND t.IsModeratorOnly = TRUE
          )
     END) AS ModeratorTags,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM PostLinks pl 
            WHERE pl.PostId = pa.Id 
                AND pl.LinkTypeId = 3
        ) THEN 'Duplicate' 
        ELSE 'Original' 
    END AS PostStatus,
    RANK() OVER (ORDER BY us.Reputation DESC) AS GlobalRank
FROM UserStats us
LEFT JOIN PostAnalysis pa ON us.Id = pa.OwnerUserId
LEFT JOIN PostHistory ph 
    ON pa.Id = ph.PostId 
    AND ph.PostHistoryTypeId = 10 
    AND ph.CreationDate = (SELECT MAX(ph2.CreationDate) FROM PostHistory ph2 WHERE ph2.PostId = pa.Id)
WHERE (pa.Score > 50) OR (us.GoldBadges > 5)
UNION ALL
SELECT 
    'INACTIVE_USER' AS DisplayName,
    0 AS GoldBadges,
    0 AS Upvotes,
    CAST(NULL AS INTEGER) AS PostScore,
    CAST(NULL AS INTEGER) AS CodeSnippets,
    CAST(NULL AS INTEGER) AS Editors,
    CAST(NULL AS INTEGER) AS CommentCount,
    CAST(NULL AS NUMERIC) AS AvgAnswers,
    CAST(NULL AS INTEGER) AS TagCount,
    CAST(NULL AS VARCHAR(4000)) AS ModeratorTags,
    'N/A' AS PostStatus,
    999999 AS GlobalRank
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
    AND NOT EXISTS (SELECT 1 FROM Comments c WHERE c.UserId = u.Id)
ORDER BY GlobalRank ASC, PostScore DESC NULLS LAST;