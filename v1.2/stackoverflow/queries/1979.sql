WITH RecursiveTaggedCommons AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST) AS rn
    FROM posts p
)
SELECT Id, OwnerUserId, Title, Tags, Tag, rn
FROM RecursiveTaggedCommons;