-- {"query": "3292.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2496} 
WITH UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AnswerScoreSum,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(*) AS TotalBadges,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 1) AS GoldBadgeList
    FROM Badges b
    GROUP BY b.UserId
),
UserVoteStats AS (
    SELECT
        v.UserId,
        COUNT(*) AS VoteCount,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        SUM(CASE WHEN vt.Id = 5 THEN 1 ELSE 0 END) AS FavoritesGiven
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.UserId
),
RecentAcceptedAnswer AS (
    SELECT
        a.OwnerUserId AS UserId,
        a.Id AS AnswerId,
        a.CreationDate AS AnswerDate,
        q.Title AS QuestionTitle,
        ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId ORDER BY a.CreationDate DESC) AS rn
    FROM Posts a
    JOIN Posts q ON q.Id = a.ParentId
    WHERE a.PostTypeId = 2
      AND q.AcceptedAnswerId = a.Id
      AND a.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
),
TopTagStats AS (
    SELECT
        t.TagName,
        t.Count,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.Count > 1000
)
SELECT
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.AnswerScoreSum,
    COALESCE(ubs.TotalBadges,0)          AS TotalBadges,
    COALESCE(ubs.GoldBadges,0)           AS GoldBadges,
    COALESCE(ubs.SilverBadges,0)         AS SilverBadges,
    COALESCE(ubs.BronzeBadges,0)         AS BronzeBadges,
    COALESCE(ubs.GoldBadgeList,'')       AS GoldBadgeList,
    COALESCE(uvs.VoteCount,0)            AS VoteCount,
    COALESCE(uvs.UpVotesGiven,0)         AS UpVotesGiven,
    COALESCE(uvs.DownVotesGiven,0)       AS DownVotesGiven,
    ra.AnswerId                         AS RecentAcceptedAnswerId,
    ra.QuestionTitle                     AS RecentAcceptedQuestionTitle,
    DATE_PART('day', cast('2024-10-01 12:34:56' as timestamp) - COALESCE(ra.AnswerDate, ups.LastPostDate, ups.CreationDate)) AS DaysSinceLastActivity,
    RANK() OVER (
        ORDER BY (
            ups.AnswerScoreSum * 0.6
            + ups.AnswerCount   * 0.3
            + COALESCE(ubs.GoldBadges,0) * 5
            + COALESCE(uvs.VoteCount,0) * 0.1
        ) DESC
    ) AS OverallRank
FROM UserPostStats ups
LEFT JOIN UserBadgeStats ubs ON ubs.UserId = ups.UserId
LEFT JOIN UserVoteStats uvs ON uvs.UserId = ups.UserId
LEFT JOIN (
    SELECT * FROM RecentAcceptedAnswer WHERE rn = 1
) ra ON ra.UserId = ups.UserId
WHERE ups.Reputation >= 1000
  AND (ups.AnswerCount > 0 OR ups.QuestionCount > 0)

UNION ALL

SELECT
    NULL                                   AS UserId,
    tt.TagName                             AS DisplayName,
    NULL                                   AS Reputation,
    NULL                                   AS QuestionCount,
    NULL                                   AS AnswerCount,
    NULL                                   AS AnswerScoreSum,
    NULL                                   AS TotalBadges,
    NULL                                   AS GoldBadges,
    NULL                                   AS SilverBadges,
    NULL                                   AS BronzeBadges,
    NULL                                   AS GoldBadgeList,
    NULL                                   AS VoteCount,
    NULL                                   AS UpVotesGiven,
    NULL                                   AS DownVotesGiven,
    NULL                                   AS RecentAcceptedAnswerId,
    NULL                                   AS RecentAcceptedQuestionTitle,
    NULL                                   AS DaysSinceLastActivity,
    tt.TagRank                             AS OverallRank
FROM TopTagStats tt
ORDER BY OverallRank ASC
LIMIT 100;