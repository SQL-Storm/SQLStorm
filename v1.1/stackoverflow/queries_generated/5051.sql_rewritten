-- {"query": "5051.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 851} 
WITH TopUserBadges AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM
        Users u
        LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE
        u.Reputation > 2000
    GROUP BY
        u.Id, u.DisplayName
    HAVING
        COUNT(b.Id) > 5
),
MostActiveQuestions AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.ViewCount,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS ActivityRank
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1 -- Only questions
        AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
),
VoteStats AS (
    SELECT
        p.Id AS PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        AVG(CASE WHEN v.VoteTypeId IN (2,3) THEN EXTRACT(epoch FROM v.CreationDate - p.CreationDate)/3600 END) AS HoursToVote
    FROM
        Posts p
        LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE
        p.PostTypeId IN (1,2)
    GROUP BY
        p.Id, p.CreationDate
),
TagSpread AS (
    SELECT
        p.Id as PostId,
        ARRAY_LENGTH(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1) AS TagCount
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
        AND p.Tags IS NOT NULL
)
SELECT
    u.UserId,
    u.DisplayName,
    u.BadgeCount,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    q.Title AS TopQuestionTitle,
    q.ViewCount AS TopQuestionViews,
    ts.UpVotes,
    ts.DownVotes,
    ts.HoursToVote,
    tg.TagCount,
    CASE
        WHEN COALESCE(ts.UpVotes, 0) > COALESCE(ts.DownVotes, 0)
            THEN 'Popular'
        WHEN ts.UpVotes IS NULL AND ts.DownVotes IS NULL
            THEN 'No votes'
        ELSE 'Unpopular'
    END AS VoteStatus,
    b.Name AS MostRecentBadgeName,
    EXTRACT(DAY FROM (cast('2024-10-01 12:34:56' as timestamp) - u.LastBadgeDate)) AS DaysSinceLastBadge,
    ROW_NUMBER() OVER (ORDER BY (u.BadgeCount + COALESCE(ts.UpVotes,0) - COALESCE(ts.DownVotes,0)) DESC) AS WeightedRank
FROM
    TopUserBadges u
    LEFT JOIN LATERAL (
        SELECT
            q.PostId,
            q.Title,
            q.ViewCount
        FROM
            MostActiveQuestions q
        WHERE
            q.OwnerUserId = u.UserId
        ORDER BY
            q.ActivityRank
        LIMIT 1
    ) q ON TRUE
    LEFT JOIN VoteStats ts ON q.PostId = ts.PostId
    LEFT JOIN TagSpread tg ON q.PostId = tg.PostId
    LEFT JOIN LATERAL (
        SELECT Name
        FROM Badges
        WHERE UserId = u.UserId
        ORDER BY Date DESC NULLS LAST
        LIMIT 1
    ) b ON TRUE
ORDER BY
    WeightedRank
LIMIT 50;