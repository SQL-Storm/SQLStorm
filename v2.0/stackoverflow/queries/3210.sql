WITH 
UserStats AS (
    SELECT 
        u.Id                                       AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(pq.QuestionCount, 0)               AS QuestionCount,
        COALESCE(pq.AnswerCount, 0)                 AS AnswerCount,
        COALESCE(bc.GoldBadgeCount, 0)              AS GoldBadgeCount,
        COALESCE(ps.TotalScore, 0)                  AS TotalPostScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank,
        AVG(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) 
            OVER (PARTITION BY u.Id)               AS AvgUpVotesPerUser
    FROM Users u
    LEFT JOIN (
        SELECT 
            OwnerUserId,
            SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
            SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
        FROM Posts
        GROUP BY OwnerUserId
    ) pq ON pq.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT 
            UserId,
            COUNT(*) FILTER (WHERE Class = 1) AS GoldBadgeCount
        FROM Badges
        GROUP BY UserId
    ) bc ON bc.UserId = u.Id
    LEFT JOIN (
        SELECT 
            OwnerUserId,
            SUM(Score) AS TotalScore
        FROM Posts
        GROUP BY OwnerUserId
    ) ps ON ps.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
),
RecentClosedQuestions AS (
    SELECT 
        ph.PostId,
        p.Title,
        ph.CreationDate AS ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN Posts p ON p.Id = ph.PostId
    WHERE ph.PostHistoryTypeId = 10
      AND p.PostTypeId = 1
),
LatestUserPost AS (
    SELECT 
        p.OwnerUserId,
        p.Id AS LatestPostId,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.RepRank,
    us.QuestionCount,
    us.AnswerCount,
    us.GoldBadgeCount,
    us.TotalPostScore,
    COALESCE(rc.Title, 'No recent closures')        AS RecentClosedTitle,
    CASE 
        WHEN us.QuestionCount = 0 THEN NULL
        ELSE us.AnswerCount * 1.0 / us.QuestionCount
    END                                            AS AnswerToQuestionRatio,
    (SELECT COUNT(*) 
     FROM Comments c 
     WHERE c.UserId = us.UserId 
       AND c.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '30' DAY) 
                                                    AS RecentCommentCount
FROM UserStats us
LEFT JOIN RecentClosedQuestions rc 
       ON rc.PostId = (
              SELECT p.Id
              FROM Posts p
              WHERE p.OwnerUserId = us.UserId 
                AND p.PostTypeId = 1
              ORDER BY p.CreationDate DESC
              LIMIT 1
          )
       AND rc.rn = 1
WHERE us.Reputation > 1000
  AND (us.GoldBadgeCount > 0 OR us.TotalPostScore > 500)

UNION ALL

SELECT 
    NULL                                           AS UserId,
    'Aggregated Totals'                            AS DisplayName,
    NULL                                           AS Reputation,
    NULL                                           AS RepRank,
    SUM(us.QuestionCount)                          AS QuestionCount,
    SUM(us.AnswerCount)                            AS AnswerCount,
    SUM(us.GoldBadgeCount)                         AS GoldBadgeCount,
    SUM(us.TotalPostScore)                         AS TotalPostScore,
    NULL                                           AS RecentClosedTitle,
    NULL                                           AS AnswerToQuestionRatio,
    NULL                                           AS RecentCommentCount
FROM UserStats us
WHERE us.Reputation > 1000;