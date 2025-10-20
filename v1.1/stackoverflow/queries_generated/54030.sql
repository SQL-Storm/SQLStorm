-- {"query": "54030.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 3468} 

WITH user_metrics AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS Questions,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS Answers,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) OVER (PARTITION BY u.Id) AS MedianScore
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
    JOIN PostHistory ph ON ph.Text::int = cr.Id
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
