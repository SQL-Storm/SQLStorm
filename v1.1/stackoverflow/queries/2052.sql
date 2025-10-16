WITH ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE
        u.LastAccessDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY
        u.Id, u.DisplayName, u.Reputation
),
PopularTags AS (
    SELECT
        t.TagName,
        COUNT(pt.PostId) AS UsageCount
    FROM
        Tags t
    INNER JOIN LATERAL (
        SELECT
            ARRAY_POSITION(string_to_array(SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags)-2)), '><'), t.TagName) AS pos,
            p.Id AS PostId
        FROM
            Posts p
        WHERE
            p.PostTypeId = 1
    ) pt ON pt.pos IS NOT NULL
    WHERE
        t.IsModeratorOnly = FALSE
    GROUP BY
        t.TagName
    HAVING
        COUNT(pt.PostId) > 1000
),
TopParticipatedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        COALESCE((SELECT MAX(c.Score) FROM Comments c WHERE c.PostId = p.Id), 0) AS MaxCommentScore,
        p.Tags,
        p.CreationDate
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 month'
)
SELECT
    au.UserId,
    au.DisplayName,
    au.Reputation,
    au.PostCount,
    pp.Title AS RecentQuestion,
    pp.MaxCommentScore,
    string_agg(pt.TagName, ', ') AS PopularTagsUsed,
    pp.CreationDate AS QuestionCreationDate,
    pq.TagArray
FROM
    ActiveUsers AS au
JOIN Posts AS upp ON au.UserId = upp.OwnerUserId
JOIN TopParticipatedPosts AS pp ON upp.Id = pp.PostId
JOIN LATERAL (
    SELECT
        string_to_array(SUBSTRING(pp.Tags FROM 2 FOR (LENGTH(pp.Tags)-2)), '><') AS TagArray
) AS pq ON true
JOIN PopularTags pt ON pt.TagName = ANY (pq.TagArray)
WHERE
    au.Reputation > 1000
    AND (pp.MaxCommentScore > 5 OR pp.MaxCommentScore IS NULL)
    AND EXISTS (
        SELECT 1
        FROM Votes v
        WHERE v.PostId = pp.PostId
          AND v.VoteTypeId = 2
          AND v.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 month'
    )
GROUP BY
    au.UserId,
    au.DisplayName,
    au.Reputation,
    au.PostCount,
    pp.Title,
    pp.MaxCommentScore,
    pp.CreationDate,
    pq.TagArray
ORDER BY
    au.Reputation DESC,
    au.PostCount DESC,
    pq.TagArray;