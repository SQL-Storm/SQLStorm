-- {"query": "43043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 525} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.ViewCount) AS AvgViewCount,
        COUNT(DISTINCT ph.Id) AS EditCount,
        MAX(b.Date) AS LastBadgeDate,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6, 8)
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
TopContributors AS (
    SELECT 
        UserId,
        DisplayName,
        QuestionCount,
        AnswerCount,
        TotalScore,
        AvgViewCount,
        EditCount,
        LastBadgeDate,
        UpVotesReceived,
        DownVotesReceived,
        RANK() OVER (ORDER BY TotalScore DESC, UpVotesReceived DESC) AS Rank
    FROM UserActivity
)
SELECT 
    tc.UserId,
    tc.DisplayName,
    tc.QuestionCount,
    tc.AnswerCount,
    tc.TotalScore,
    tc.AvgViewCount,
    tc.EditCount,
    tc.LastBadgeDate,
    tc.UpVotesReceived,
    tc.DownVotesReceived,
    b.Name AS LastBadgeEarned
FROM TopContributors tc
LEFT JOIN Badges b ON tc.UserId = b.UserId AND tc.LastBadgeDate = b.Date
WHERE tc.Rank <= 10
ORDER BY tc.Rank;
