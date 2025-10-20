-- {"query": "57033.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 692} 

WITH RecentActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) AS VoteCount,
        MAX(p.LastActivityDate) AS LastActivityDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
	LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE
        u.LastAccessDate >= NOW() - INTERVAL '30 days'
    GROUP BY
        u.Id, u.Reputation, u.DisplayName
), TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        COUNT(p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews
    FROM
        Tags t
    JOIN
        Posts p ON t.Id = ANY(string_to_array(p.Tags, '><'))
    WHERE
        p.PostTypeId = 1
    GROUP BY
        t.TagName, t.Count
    ORDER BY
        TotalViews DESC
    LIMIT 10
), UserActivity AS (
    SELECT
        ra.UserId,
        ra.DisplayName,
        ra.PostCount,
        ra.CommentCount,
        ra.VoteCount,
        ra.LastActivityDate,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBountyAmount,
        COALESCE(COUNT(b.Id), 0) AS BadgeCount
    FROM
        RecentActiveUsers ra
    LEFT JOIN
        Votes v ON ra.UserId = v.UserId AND v.VoteTypeId IN (8, 9)
	LEFT JOIN  Badges b ON ra.UserId = b.UserId
    GROUP BY
        ra.UserId, ra.DisplayName, ra.PostCount, ra.CommentCount, ra.VoteCount, ra.LastActivityDate
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.PostCount,
    ua.CommentCount,
    ua.VoteCount,
    ua.LastActivityDate,
    ua.TotalBountyAmount,
    ua.BadgeCount,
    t.TagName,
    t.QuestionCount,
    t.AvgScore,
    t.TotalViews
FROM
    UserActivity ua
CROSS JOIN
    TopTags t
ORDER BY
    ua.TotalBountyAmount DESC,
    t.TotalViews DESC
LIMIT 50;
