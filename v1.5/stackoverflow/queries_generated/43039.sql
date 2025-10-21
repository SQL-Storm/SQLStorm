-- {"query": "43039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 525} 

WITH UserActivity AS (
    SELECT u.Id, 
           u.DisplayName, 
           u.Reputation, 
           COUNT(DISTINCT b.Id) AS BadgeCount,
           SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    GROUP BY u.Id
),
PostSummary AS (
    SELECT p.OwnerUserId,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
           AVG(p.Score) AS AvgScore,
           MAX(p.ViewCount) AS MaxViewCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY p.OwnerUserId
),
TopContributors AS (
    SELECT ua.Id, 
           ua.DisplayName, 
           ua.Reputation, 
           ua.BadgeCount,
           COALESCE(ps.QuestionCount, 0) AS QuestionCount,
           COALESCE(ps.AnswerCount, 0) AS AnswerCount,
           COALESCE(ps.AvgScore, 0) AS AvgScore,
           COALESCE(ps.MaxViewCount, 0) AS MaxViewCount,
           ROW_NUMBER() OVER (ORDER BY COALESCE(ps.QuestionCount, 0) + COALESCE(ps.AnswerCount, 0) DESC) AS Rank
    FROM UserActivity ua
    LEFT JOIN PostSummary ps ON ua.Id = ps.OwnerUserId
    WHERE ua.EditCount > 10
)
SELECT tc.Id, 
       tc.DisplayName, 
       tc.Reputation, 
       tc.BadgeCount,
       tc.QuestionCount,
       tc.AnswerCount,
       tc.AvgScore,
       tc.MaxViewCount
FROM TopContributors tc
WHERE tc.Rank <= 10;
