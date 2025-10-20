WITH RECURSIVE RecursiveVoteSums AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        u.Id AS UserId,
        u.DisplayName,
        v.VoteTypeId,
        COUNT(v.Id) AS VoteCount,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBounty
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.CreationDate > TIMESTAMP '2015-01-01 00:00:00'
    GROUP BY p.Id, p.PostTypeId, u.Id, u.DisplayName, v.VoteTypeId

    UNION ALL

    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      u.Id AS UserId,
      u.DisplayName,
      rvs.VoteTypeId,
      rvs.VoteCount,
      rvs.TotalBounty
    FROM Posts p
    JOIN Votes v ON v.PostId = p.Id
    JOIN Users u ON p.OwnerUserId = u.Id
    JOIN RecursiveVoteSums rvs ON rvs.PostId = v.PostId
        AND rvs.VoteTypeId IS NULL
),

AggregatedCTE AS (
    SELECT
        p.Id,
        p.PostTypeId,
        COALESCE((
            SELECT STRING_AGG(t.TagName, ',' ORDER BY t.Count DESC)
            FROM Tags t
            JOIN (
                -- split tags like '<tag1><tag2>' into rows without using dialect-specific function
                SELECT TRIM(value) AS TagName
                FROM (
                    SELECT
                        CASE
                            WHEN s = '' THEN NULL
                            ELSE s
                        END AS value
                    FROM (
                        SELECT
                            REGEXP_SPLIT_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2), '><') AS arr
                    ) arr_table,
                    UNNEST(arr_table.arr) AS s
                ) split_vals
            ) tag_names ON tag_names.TagName = t.TagName
        ), '') AS TopTags,
        p.OwnerUserId,
        p.CreationDate
    FROM Posts p
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate
)

SELECT
    rvs.PostId,
    rvs.PostTypeId,
    rvs.UserId,
    rvs.DisplayName,
    rvs.VoteTypeId,
    rvs.VoteCount,
    rvs.TotalBounty,
    a.TopTags,
    a.OwnerUserId,
    a.CreationDate
FROM RecursiveVoteSums rvs
JOIN AggregatedCTE a ON a.Id = rvs.PostId
GROUP BY
    rvs.PostId,
    rvs.PostTypeId,
    rvs.UserId,
    rvs.DisplayName,
    rvs.VoteTypeId,
    rvs.VoteCount,
    rvs.TotalBounty,
    a.TopTags,
    a.OwnerUserId,
    a.CreationDate;