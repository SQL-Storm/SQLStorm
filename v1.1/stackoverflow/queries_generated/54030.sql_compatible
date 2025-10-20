WITH user_metrics AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS Questions,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS Answers,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        -- use percentile_cont as a grouped aggregate without OVER by computing per user via subquery
        (
            SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p2.Score)
            FROM Posts p2
            WHERE p2.OwnerUserId = u.Id
        ) AS MedianScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
tag_metrics AS (
    SELECT
        t.TagName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS ACount,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVoteCount,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVoteCount
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY t.TagName
),
close_reason_summary AS (
    SELECT
        cr.Name AS Reason,
        COUNT(*) AS Total
    FROM CloseReasonTypes cr
    JOIN PostHistory ph ON CAST(ph.Text AS INTEGER) = cr.Id
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY cr.Name
)
SELECT
    um.Id,
    um.DisplayName,
    um.Reputation,
    um.Questions,
    um.Answers,
    um.UpVotes,
    um.DownVotes,
    um.TotalScore,
    um.AvgScore,
    um.MedianScore,
    tm.TagName,
    tm.QCount,
    tm.ACount,
    tm.UpVoteCount,
    tm.DownVoteCount,
    csr.Reason,
    csr.Total
FROM user_metrics um
CROSS JOIN tag_metrics tm
CROSS JOIN close_reason_summary csr
ORDER BY um.Reputation DESC
LIMIT 100;