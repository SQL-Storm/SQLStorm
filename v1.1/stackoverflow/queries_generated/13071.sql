-- {"query": "13071.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 937} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersProvided,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (5, 8) THEN 1 ELSE 0 END) AS EditsMade,
        ROW_NUMBER() OVER (ORDER BY SUM(CASE WHEN ph.PostHistoryTypeId IN (5, 8) THEN 1 ELSE 0 END) DESC) AS EditRank,
        AVG(p.Score) AS AvgPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND p.Id = ph.PostId
    WHERE p.PostTypeId IN (1, 2) AND u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
TopPerformingUsers AS (
    SELECT 
        UserId,
        DisplayName,
        QuestionsAsked,
        AnswersProvided,
        EditsMade,
        AvgPostScore
    FROM UserActivity
    WHERE EditRank <= 100
),
PostFeedback AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS CloseVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COALESCE(NULLIF(MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0), 0) AS HasGoldBadge
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Badges b ON p.OwnerUserId = b.UserId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, p.OwnerUserId
),
UserPerformance AS (
    SELECT 
        tpu.UserId,
        tpu.DisplayName,
        tpu.QuestionsAsked,
        tpu.AnswersProvided,
        tpu.EditsMade,
        tpu.AvgPostScore,
        COALESCE(pf.CloseVotes, 0) AS TotalCloseVotes,
        COALESCE(pf.UpVotes, 0) AS TotalUpVotes,
        COALESCE(pf.DownVotes, 0) AS TotalDownVotes,
        MAX(pf.HasGoldBadge) AS HasGoldBadge
    FROM TopPerformingUsers tpu
    LEFT JOIN PostFeedback pf ON tpu.UserId = pf.OwnerUserId
    GROUP BY tpu.UserId, tpu.DisplayName, tpu.QuestionsAsked, tpu.AnswersProvided, tpu.EditsMade, tpu.AvgPostScore, pf.CloseVotes, pf.UpVotes, pf.DownVotes
)
SELECT 
    up.UserId,
    up.DisplayName,
    up.QuestionsAsked,
    up.AnswersProvided,
    up.EditsMade,
    up.AvgPostScore,
    up.TotalCloseVotes,
    up.TotalUpVotes,
    up.TotalDownVotes,
    CASE WHEN up.HasGoldBadge = 1 THEN 'Yes' ELSE 'No' END AS HasGoldBadge,
    DENSE_RANK() OVER (ORDER BY up.TotalUpVotes DESC, up.EditsMade DESC) AS PerformanceRank
FROM UserPerformance up
WHERE up.AvgPostScore > (SELECT AVG(AvgPostScore) FROM UserPerformance WHERE AvgPostScore > 0)
ORDER BY PerformanceRank;
