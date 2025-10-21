WITH
TopActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        SUM(p.Score) AS aggregatescore
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(p.Id) > 50
),
PostEditingStats AS (
    SELECT
        ph.PostId,
        COUNT(*) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    JOIN Posts p ON p.Id = ph.PostId
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
      AND ph.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
    GROUP BY ph.PostId
),
PopularTags AS (
    SELECT
        TRIM(BOTH '>' FROM
            REGEXP_REPLACE(
                REGEXP_REPLACE(p.Tags, '^<', ''), '--', '', 'g'
            )
        ) AS TagName,
        COUNT(*) AS TagPostCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
    GROUP BY TRIM(BOTH '>' FROM REGEXP_REPLACE(REGEXP_REPLACE(p.Tags, '^<', ''), '--', '', 'g'))
    HAVING COUNT(*) > 100
)
SELECT
    u.UserId,
    u.DisplayName,
    u.TotalPosts,
    u.Questions,
    u.Answers,
    u.aggregatescore AS AggregateScore,
    ROUND(AVG(COALESCE(es.EditCount, 0))::NUMERIC, 2) AS AvgEditsPerPost,
    COUNT(DISTINCT t.TagName) AS DistinctTagsUsed,
    MAX(es.LastEditDate) AS MostRecentEdit
FROM TopActiveUsers u
LEFT JOIN Posts p ON p.OwnerUserId = u.UserId
    AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
LEFT JOIN PostEditingStats es ON es.PostId = p.Id
LEFT JOIN (
    SELECT
        TRIM(BOTH '>' FROM
            UNNEST(string_to_array(substring(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))) AS TagName
    FROM Posts p
) t ON TRUE
INNER JOIN PopularTags pop ON pop.TagName = t.TagName
GROUP BY
    u.UserId,
    u.DisplayName,
    u.TotalPosts,
    u.Questions,
    u.Answers,
    u.aggregatescore
HAVING COUNT(DISTINCT t.TagName) >= 5
ORDER BY u.aggregatescore DESC, u.TotalPosts DESC
FETCH FIRST 25 ROWS ONLY;