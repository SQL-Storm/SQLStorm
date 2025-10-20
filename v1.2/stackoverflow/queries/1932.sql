WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        rp.FirstPostCreator,
        pawr.PostAuthorsCount
    FROM
        Tags t
    LEFT JOIN (
        SELECT
            Tags,
            dense_rank() OVER (ORDER BY CreationDate) AS IORowed_date,
            unnest(string_to_array(substring(Tags, 2, length(Tags) - 2), '><')) AS tname,
            OwnerUserId AS FirstPostCreator,
            Id AS PostId
        FROM Posts
    ) rp
        ON rp.tname = t.TagName
    LEFT JOIN (
        SELECT
            Id AS PostId,
            COUNT(DISTINCT OwnerUserId) AS PostAuthorsCount
        FROM Posts
        GROUP BY Id
    ) pawr
        ON pawr.PostId = rp.PostId
)
SELECT
    Id,
    TagName,
    Count,
    FirstPostCreator,
    PostAuthorsCount
FROM RecursiveTagHierarchy
GROUP BY
    Id,
    TagName,
    Count,
    FirstPostCreator,
    PostAuthorsCount;