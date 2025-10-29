WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesReceived,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotesReceived,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
RecentActivity AS (
    SELECT 
        u.Id,
        COUNT(c.Id) AS RecentComments,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS RecentCloses
    FROM Users u
    LEFT JOIN Comments c
        ON c.UserId = u.Id
        AND c.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
    LEFT JOIN PostHistory ph
        ON ph.UserId = u.Id
        AND ph.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
    GROUP BY u.Id
),
TagStats AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgScore,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AnsweredCount
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
Combined AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.UpVotesReceived,
        us.DownVotesReceived,
        us.BadgeCount,
        us.LastPostDate,
        COALESCE(ra.RecentComments, 0) AS RecentComments,
        COALESCE(ra.RecentCloses, 0) AS RecentCloses,
        CASE 
            WHEN us.DownVotesReceived = 0 THEN NULL
            ELSE ROUND(CAST(us.UpVotesReceived AS numeric) / CAST(us.DownVotesReceived AS numeric), 2)
        END AS UpDownRatio,
        ROW_NUMBER() OVER (PARTITION BY us.Reputation ORDER BY us.UpVotesReceived DESC) AS RankByUpvotes
    FROM UserStats us
    LEFT JOIN RecentActivity ra ON ra.Id = us.Id
    WHERE us.Reputation > 1000
),
FinalCTE AS (
    SELECT 
        c.Id,
        c.DisplayName,
        c.Reputation,
        c.UpVotesReceived,
        c.DownVotesReceived,
        c.BadgeCount,
        c.LastPostDate,
        c.RecentComments,
        c.RecentCloses,
        c.UpDownRatio,
        c.RankByUpvotes,
        COALESCE(t.AvgScore, 0) AS TagAvgScore,
        COALESCE(t.AnsweredCount, 0) AS TagAnsweredCount
    FROM Combined c
    LEFT JOIN LATERAL (
        SELECT ts.AvgScore, ts.AnsweredCount
        FROM TagStats ts
        WHERE ts.TagName = ANY (
            string_to_array(
                (SELECT p.Tags 
                 FROM Posts p 
                 WHERE p.OwnerUserId = c.Id 
                 ORDER BY p.CreationDate DESC 
                 LIMIT 1), 
                '><')
        )
        ORDER BY ts.QuestionCount DESC
        LIMIT 1
    ) t ON TRUE
)
SELECT *
FROM FinalCTE
WHERE (UpDownRatio IS NOT NULL AND UpDownRatio > 1.5)
   OR RecentCloses > 5
UNION ALL
SELECT NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
ORDER BY Reputation DESC, RankByUpvotes ASC
LIMIT 100;