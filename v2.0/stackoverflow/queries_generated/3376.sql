-- {"query": "3376.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2048} 
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(pcnt.QuestionCount,0) AS QuestionCount,
        COALESCE(pcnt.AnswerCount,0)   AS AnswerCount,
        COALESCE(bcnt.GoldBadgeCount,0)   AS GoldBadgeCount,
        COALESCE(bcnt.SilverBadgeCount,0) AS SilverBadgeCount,
        COALESCE(vcnt.UpVoteCount,0)   AS UpVoteCount,
        COALESCE(vcnt.DownVoteCount,0) AS DownVoteCount,
        COALESCE(cmt.CommentCount,0)   AS CommentCount,
        AVG(COALESCE(p.Score,0)) OVER (PARTITION BY u.Id) AS AvgPostScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COALESCE(pcnt.QuestionCount,0) DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN (
        SELECT 
            OwnerUserId,
            SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
            SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
        FROM Posts
        GROUP BY OwnerUserId
    ) pcnt ON pcnt.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT 
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount
        FROM Badges
        GROUP BY UserId
    ) bcnt ON bcnt.UserId = u.Id
    LEFT JOIN (
        SELECT 
            UserId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
        FROM Votes
        GROUP BY UserId
    ) vcnt ON vcnt.UserId = u.Id
    LEFT JOIN (
        SELECT 
            UserId,
            COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY UserId
    ) cmt ON cmt.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
)
SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.GoldBadgeCount,
    us.SilverBadgeCount,
    us.UpVoteCount,
    us.DownVoteCount,
    us.CommentCount,
    ROUND(us.AvgPostScore,2) AS AvgPostScore,
    us.ReputationRank,
    CASE 
        WHEN us.ReputationRank <= 10 THEN 'Top10'
        WHEN us.ReputationRank <= 100 THEN 'Top100'
        ELSE 'Other'
    END AS RankGroup,
    COALESCE(NULLIF(us.DisplayName, ''), 'Anonymous') AS SafeDisplayName,
    CONCAT('User_', us.Id) AS UserKey,
    (SELECT COUNT(*) 
     FROM Posts p2 
     WHERE p2.OwnerUserId = us.Id 
       AND p2.PostTypeId = 1 
       AND p2.CreationDate >= DATEADD(year, -1, CURRENT_TIMESTAMP)
    ) AS RecentQuestionCount
FROM UserStats us
WHERE us.Reputation > 1000
  AND (us.QuestionCount + us.AnswerCount) > 0
  AND (us.GoldBadgeCount + us.SilverBadgeCount) > 0
ORDER BY us.ReputationRank
OFFSET 0 ROWS FETCH NEXT 50 ROWS ONLY

UNION ALL

SELECT 
    -1 AS Id,
    'Aggregated' AS DisplayName,
    SUM(us.Reputation) AS Reputation,
    SUM(us.QuestionCount) AS QuestionCount,
    SUM(us.AnswerCount) AS AnswerCount,
    SUM(us.GoldBadgeCount) AS GoldBadgeCount,
    SUM(us.SilverBadgeCount) AS SilverBadgeCount,
    SUM(us.UpVoteCount) AS UpVoteCount,
    SUM(us.DownVoteCount) AS DownVoteCount,
    SUM(us.CommentCount) AS CommentCount,
    NULL AS AvgPostScore,
    NULL AS ReputationRank,
    NULL AS RankGroup,
    NULL AS SafeDisplayName,
    NULL AS UserKey,
    NULL AS RecentQuestionCount
FROM UserStats us
WHERE us.Reputation > 1000
  AND (us.QuestionCount + us.AnswerCount) > 0;