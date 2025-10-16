WITH UserPostActivity AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        p.PostTypeId,
        COUNT(*) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.ViewCount) AS MaxViewCount,
        RANK() OVER (PARTITION BY u.Id ORDER BY MAX(p.LastActivityDate) DESC) AS RecentActivityRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 100 AND p.PostTypeId IN (1, 2)
    GROUP BY u.Id, u.DisplayName, p.PostTypeId
),
TagPairs AS (
    /* split Tags into pairs of (PostId, TagName) using portable string functions */
    SELECT
        p.Id AS PostId,
        TRIM(tag) AS TagName
    FROM Posts p,
    LATERAL (
        -- normalize tags string: remove surrounding < and > if present, then split on '><'
        SELECT
            CASE WHEN p.Tags IS NULL OR p.Tags = '' THEN NULL
                 ELSE split_value
            END AS tag
        FROM (
            SELECT
                NULLIF(
                    regexp_replace(
                        CASE
                            WHEN SUBSTRING(p.Tags FROM 1 FOR 1) = '<' AND SUBSTRING(p.Tags FROM CHAR_LENGTH(p.Tags) FOR 1) = '>' THEN SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2)
                            ELSE COALESCE(p.Tags, '')
                        END,
                        '><', '|', 'g'
                    ),
                    ''
                ) AS joined
        ) norm
        CROSS JOIN LATERAL (
            -- Split the joined string on '|' into rows using a recursive CTE and standard POSITION/SUBSTRING
            SELECT s.value AS split_value
            FROM (
                WITH RECURSIVE split_cte(rest, value) AS (
                    SELECT norm.joined || '|' , NULL
                    WHERE norm.joined IS NOT NULL
                    UNION ALL
                    SELECT
                        SUBSTRING(rest FROM POSITION('|' IN rest) + 1),
                        TRIM(SUBSTRING(rest FROM 1 FOR POSITION('|' IN rest) - 1))
                    FROM split_cte
                    WHERE rest IS NOT NULL AND POSITION('|' IN rest) > 0
                )
                SELECT value FROM split_cte WHERE value IS NOT NULL
            ) s
        ) parts
    ) split_tags
    WHERE p.Tags IS NOT NULL AND p.Tags <> ''
),
TagPopularity AS (
    SELECT 
        tp.TagName,
        COUNT(*) AS TagFrequency,
        AVG(p.Score) AS AvgTagScore
    FROM TagPairs tp
    JOIN Posts p ON p.Id = tp.PostId
    GROUP BY tp.TagName
)
SELECT 
    upa.UserId,
    upa.DisplayName,
    tp.TagName,
    upa.PostCount,
    upa.AvgPostScore,
    tp.TagFrequency,
    tp.AvgTagScore,
    CASE 
        WHEN upa.MaxViewCount > 10000 THEN 'High Impact'
        WHEN upa.MaxViewCount BETWEEN 1000 AND 10000 THEN 'Medium Impact'
        ELSE 'Low Impact'
    END AS PostImpactCategory,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.UserId = upa.UserId AND v.VoteTypeId IN (2, 3)
        ), 0
    ) AS TotalVotes,
    upa.PostTypeId,
    upa.MaxViewCount,
    upa.RecentActivityRank
FROM UserPostActivity upa
JOIN TagPopularity tp ON EXISTS (
    SELECT 1 
    FROM Posts p 
    WHERE p.OwnerUserId = upa.UserId 
      AND p.Tags IS NOT NULL
      AND POSITION(tp.TagName IN p.Tags) > 0
)
WHERE upa.RecentActivityRank = 1 
  AND upa.AvgPostScore > (
      SELECT AVG(Score) 
      FROM Posts 
      WHERE PostTypeId = upa.PostTypeId
  )
ORDER BY upa.PostCount * tp.TagFrequency DESC
LIMIT 100;