WITH ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        COUNT(p.Id) AS PostCount,
        SUM(p.Score) AS TotalPostScore,
        MAX(p.LastActivityDate) AS LastActivity,
        u.Reputation
    FROM
        Users u
    JOIN
        Posts p ON u.Id = p.OwnerUserId
    WHERE
        p.PostTypeId = 1
    GROUP BY
        u.Id, u.Reputation
    HAVING
        COUNT(p.Id) > 10
        AND MAX(p.LastActivityDate) > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 day')
),
HighReputationUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation
    FROM
        Users u
    WHERE
        u.Reputation > 5000
),
TopTags AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS PostCount
    FROM
        Tags t
    JOIN
        Posts p ON p.Tags LIKE ('%' || '<' || t.TagName || '>' || '%')
    WHERE
        p.PostTypeId = 1
    GROUP BY
        t.TagName
    ORDER BY
        PostCount DESC
    LIMIT 10
),
PopularPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        u.DisplayName AS Author,
        p.OwnerUserId
    FROM
        Posts p
    JOIN
        Users u ON p.OwnerUserId = u.Id
    WHERE
        p.PostTypeId = 1
    ORDER BY
        (p.Score + p.ViewCount) DESC
    LIMIT 50
),
RecentActivity AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        l.Name as HistoryActionDescription,
        ph.CreationDate
    FROM
        PostHistory ph
    JOIN
        Posts p ON ph.PostId = p.Id
    JOIN
        PostHistoryTypes l on l.Id  = ph.PostHistoryTypeId
    WHERE
        ph.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '7 day')
    ORDER BY
        ph.CreationDate DESC
),
CombinedMetrics AS (
    SELECT
        au.UserId,
        au.PostCount,
        au.TotalPostScore,
        au.LastActivity,
        hr.Reputation,
        tt.TagName,
        tt.PostCount AS TagPostCount,
        pp.PostId,
        pp.Title,
        pp.Score,
        pp.ViewCount,
        pp.Author,
        ra.PostId AS RecentPostId,
        ra.HistoryActionDescription,
        ra.CreationDate AS RecentActivityDate
    FROM
        ActiveUsers au
    LEFT JOIN
        HighReputationUsers hr ON au.UserId = hr.UserId
    LEFT JOIN
        PopularPosts pp ON au.UserId = pp.OwnerUserId
    LEFT JOIN
        RecentActivity ra ON pp.PostId = ra.PostId
    LEFT JOIN
        TopTags tt ON pp.Title IS NOT NULL AND pp.Title LIKE ('%' || '<' || tt.TagName || '>' || '%')
)

SELECT
    cm.UserId,
    cm.PostCount,
    cm.TotalPostScore,
    cm.LastActivity,
    cm.Reputation,
    cm.TagName,
    cm.TagPostCount,
    cm.PostId,
    cm.Title,
    cm.Score,
    cm.ViewCount,
    cm.Author,
    cm.RecentPostId,
    cm.HistoryActionDescription,
    cm.RecentActivityDate
FROM
    CombinedMetrics cm
ORDER BY
    cm.Reputation DESC,
    cm.TotalPostScore DESC,
    cm.LastActivity DESC;