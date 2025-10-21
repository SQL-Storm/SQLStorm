WITH RecentActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        MAX(p.LastActivityDate) AS LastActivity
    FROM
        Users u
    JOIN
        Posts p ON u.Id = p.OwnerUserId
    WHERE
        p.LastActivityDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 DAY'
    GROUP BY
        u.Id, u.Reputation, u.DisplayName
),
TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.PostTypeId,
        COUNT(v.Id)
        AS VoteCount
    FROM
        Tags t
    JOIN
        Posts p ON t.TagName = ANY(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><'))
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    WHERE
        p.PostTypeId = 1
    GROUP BY
        t.TagName, t.Count, p.Title, p.Tags, p.Score, p.ViewCount, p.PostTypeId
)
SELECT
    rau.UserId,
    rau.DisplayName,
    rau.Reputation,
    rau.PostCount,
    rau.TotalScore,
    rau.LastActivity,
    tt.TagName,
    tt.Count AS TagCount,
    tt.Title AS PostTitle,
    tt.Tags AS PostTags,
    tt.Score AS PostScore,
    tt.ViewCount,
    SUM(tt.PostTypeId) AS PostTypeIdSum,
    tt.VoteCount
FROM
    RecentActiveUsers rau
JOIN
    TopTags tt ON tt.Tags = ANY(string_to_array(substr(tt.Tags, 2, length(tt.Tags) - 2), '><'))
GROUP BY
    rau.UserId, rau.DisplayName, rau.Reputation, rau.PostCount, rau.TotalScore, rau.LastActivity, tt.TagName, tt.Count, tt.Title, tt.Tags, tt.Score, tt.ViewCount, tt.VoteCount
ORDER BY
    rau.Reputation DESC,
    tt.Count DESC,
    tt.ViewCount
LIMIT 100;