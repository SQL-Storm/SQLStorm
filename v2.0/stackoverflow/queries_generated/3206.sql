-- {"query": "3206.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2412} 

WITH
UserBadgeStats AS (
    SELECT u.Id AS UserId,
           COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
           COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
           COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
           MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),
PostMetrics AS (
    SELECT p.OwnerUserId AS UserId,
           COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
           COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
           AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
           AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
           SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END)::decimal
               / NULLIF(COUNT(*) FILTER (WHERE p.PostTypeId = 1),0) AS AcceptanceRate,
           MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
TagPopularity AS (
    SELECT t.TagName,
           t.Count AS TagUseCount,
           COALESCE(e.Title, w.Title) AS TagExcerptTitle
    FROM Tags t
    LEFT JOIN Posts e ON e.Id = t.ExcerptPostId
    LEFT JOIN Posts w ON w.Id = t.WikiPostId
),
UserActivityWindow AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           ub.GoldBadges,
           ub.SilverBadges,
           ub.BronzeBadges,
           pm.QuestionCount,
           pm.AnswerCount,
           pm.AvgQuestionScore,
           pm.AvgAnswerScore,
           pm.AcceptanceRate,
           ub.LastBadgeDate,
           pm.LastPostDate,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, pm.AnswerCount DESC) AS ReputationRank,
           RANK() OVER (ORDER BY (pm.QuestionCount + pm.AnswerCount) DESC) AS ActivityRank
    FROM Users u
    LEFT JOIN UserBadgeStats ub ON ub.UserId = u.Id
    LEFT JOIN PostMetrics pm ON pm.UserId = u.Id
    WHERE u.Reputation > 1000
      AND (ub.GoldBadges > 0 OR ub.SilverBadges > 0)
),
RecentVotes AS (
    SELECT v.UserId,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesGiven,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesGiven,
           MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.UserId
)
SELECT ua.Id,
       ua.DisplayName,
       ua.Reputation,
       ua.ReputationRank,
       ua.ActivityRank,
       ua.GoldBadges,
       ua.SilverBadges,
       ua.BronzeBadges,
       ua.QuestionCount,
       ua.AnswerCount,
       ROUND(ua.AvgQuestionScore,2)   AS AvgQScore,
       ROUND(ua.AvgAnswerScore,2)    AS AvgAScore,
       COALESCE(ua.AcceptanceRate,0) AS AcceptanceRate,
       rv.UpVotesGiven,
       rv.DownVotesGiven,
       CASE
           WHEN rv.LastVoteDate IS NULL THEN 'Never Voted'
           ELSE TO_CHAR(rv.LastVoteDate, 'YYYY-MM-DD')
       END AS LastVoteDate,
       COALESCE(tp.TagName, 'N/A')    AS TopTag,
       tp.TagUseCount                AS TopTagUseCount
FROM UserActivityWindow ua
LEFT JOIN RecentVotes rv ON rv.UserId = ua.Id
LEFT JOIN LATERAL (
    SELECT tg.TagName, tg.TagUseCount
    FROM TagPopularity tg
    ORDER BY tg.TagUseCount DESC
    LIMIT 1
) tp ON TRUE
WHERE ua.QuestionCount + ua.AnswerCount > 0

UNION ALL

SELECT NULL                               AS Id,
       '--- Summary ---'                  AS DisplayName,
       NULL                               AS Reputation,
       NULL                               AS ReputationRank,
       NULL                               AS ActivityRank,
       SUM(ub.GoldBadges)                 AS GoldBadges,
       SUM(ub.SilverBadges)               AS SilverBadges,
       SUM(ub.BronzeBadges)               AS BronzeBadges,
       SUM(pm.QuestionCount)              AS TotalQuestions,
       SUM(pm.AnswerCount)                AS TotalAnswers,
       NULL                               AS AvgQScore,
       NULL                               AS AvgAScore,
       NULL                               AS AcceptanceRate,
       NULL                               AS UpVotesGiven,
       NULL                               AS DownVotesGiven,
       NULL                               AS LastVoteDate,
       NULL                               AS TopTag,
       NULL                               AS TopTagUseCount
FROM UserBadgeStats ub
JOIN PostMetrics pm ON pm.UserId = ub.UserId
WHERE ub.GoldBadges > 0;
