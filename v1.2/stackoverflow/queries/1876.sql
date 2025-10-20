WITH
RecursiveAdultBadges AS (
    SELECT
        b.Id,
        b.UserId,
        b.Name,
        b.Date,
        b.Class,
        u.Reputation,
        CONCAT('Build: ', ROUND(AVG(u.Reputation) OVER (PARTITION BY b.Class), 2)) AS AvgRepByClass,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn
    FROM Badges b
    JOIN Users u ON u.Id = b.UserId
    WHERE 1=1
),
PrePts AS (
    SELECT
        p.Id AS post_id,
        p.Title
    FROM Posts p
)
SELECT
    r.Id,
    r.UserId,
    r.Name,
    r.Date,
    r.Class,
    r.Reputation,
    r.AvgRepByClass,
    r.rn,
    pp.post_id,
    pp.Title
FROM RecursiveAdultBadges r
LEFT JOIN PrePts pp ON pp.post_id = r.Id
GROUP BY
    r.Id,
    r.UserId,
    r.Name,
    r.Date,
    r.Class,
    r.Reputation,
    r.AvgRepByClass,
    r.rn,
    pp.post_id,
    pp.Title;