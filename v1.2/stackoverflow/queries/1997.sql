WITH RecursiveTagHierarchy(TagName, ParentTagName, Depth) AS (
    SELECT t.TagName, CAST(NULL AS varchar), 1
    FROM Tags t
    WHERE /* placeholder filter - original comment contained non-ASCII garbage; replace with actual filter as needed */ 1 = 1
)
SELECT
    r.TagName,
    r.ParentTagName,
    r.Depth,
    p.Id AS PostId,
    p.OwnerUserId,
    p.CreationDate,
    u.Id AS UserId,
    u.DisplayName
FROM RecursiveTagHierarchy r
LEFT JOIN Posts p
    ON p.Tags LIKE '%' || r.TagName || '%'
LEFT JOIN Users u
    ON u.Id = p.OwnerUserId
GROUP BY
    r.TagName,
    r.ParentTagName,
    r.Depth,
    p.Id,
    p.OwnerUserId,
    p.CreationDate,
    u.Id,
    u.DisplayName;