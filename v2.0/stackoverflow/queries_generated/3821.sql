-- {"query": "3821.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1613} 

/* 1️⃣  Extract all questions that contain the tag <python> (case‑insensitive) */
WITH TaggedQuestions AS (
    SELECT
        p.Id                AS QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId       AS QuestionOwnerId,
        COALESCE(NULLIF(p.Tags, ''), '<>') AS RawTags,
        /* split tags string like '<tag1><tag2>' into a set */
        regexp_split_to_table(
            substring(p.Tags FROM 2 FOR length(p.Tags)-2),
            '><'
        )                     AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1                     -- only questions
      AND p.Tags ILIKE '%<python>%'
),

/* 2️⃣  Answers to those questions, plus flag if it is the accepted answer */
AnswerInfo AS (
    SELECT
        a.Id                 AS AnswerId,
        a.ParentId           AS QuestionId,
        a.OwnerUserId        AS AnswerOwnerId,
        a.Score,
        a.CreationDate,
        CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END AS IsAccepted
    FROM Posts a
    JOIN TaggedQuestions q ON a.ParentId = q.QuestionId
    WHERE a.PostTypeId = 2                     -- only answers
),

/* 3️⃣  Aggregate per answering user */
UserAnswerStats AS (
    SELECT
        u.Id                AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT a.AnswerId)                     AS AnswerCount,
        SUM(a.Score)                                   AS TotalAnswerScore,
        AVG(a.Score)                                   AS AvgAnswerScore,
        SUM(a.IsAccepted)                              AS AcceptedAnswerCount,
        MAX(a.CreationDate)                            AS LastAnswerDate,
        ROW_NUMBER() OVER (ORDER BY SUM(a.Score) DESC) AS RankByScore
    FROM Users u
    LEFT JOIN AnswerInfo a ON a.AnswerOwnerId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

/* 4️⃣  Badge totals per user – include users with zero badges */
UserBadgeAgg AS (
    SELECT
        b.UserId,
        COUNT(*)                      AS TotalBadges,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),

/* 5️⃣  Latest vote (any type) per user on their answers */
UserLatestVote AS (
    SELECT
        v.UserId,
        MAX(v.CreationDate)          AS LatestVoteDate,
        MAX(v.VoteTypeId)            AS LatestVoteTypeId
    FROM Votes v
    JOIN AnswerInfo a ON v.PostId = a.AnswerId
    GROUP BY v.UserId
),

/* 6️⃣  Combine all pieces – outer join to keep users without badges or votes */
CombinedUserStats AS (
    SELECT
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.AnswerCount,
        uas.TotalAnswerScore,
        ROUND(uas.AvgAnswerScore,2)          AS AvgAnswerScore,
        uas.AcceptedAnswerCount,
        uas.LastAnswerDate,
        uas.RankByScore,
        COALESCE(uba.TotalBadges,0)          AS TotalBadges,
        COALESCE(uba.GoldBadges,0)           AS GoldBadges,
        COALESCE(uba.SilverBadges,0)         AS SilverBadges,
        COALESCE(uba.BronzeBadges,0)         AS BronzeBadges,
        ulv.LatestVoteDate,
        CASE ulv.LatestVoteTypeId
            WHEN 1 THEN 'AcceptedByOriginator'
            WHEN 2 THEN 'UpMod'
            WHEN 3 THEN 'DownMod'
            WHEN 5 THEN 'Favorite'
            WHEN 12 THEN 'Spam'
            ELSE COALESCE(CAST(ulv.LatestVoteTypeId AS TEXT), 'None')
        END                                 AS LatestVoteType
    FROM UserAnswerStats uas
    LEFT JOIN UserBadgeAgg uba  ON uba.UserId = uas.UserId
    LEFT JOIN UserLatestVote ulv ON ulv.UserId = uas.UserId
)

/* 7️⃣  Final result – top 20 users, plus a UNION ALL with a sanity‑check set */
SELECT
    cus.UserId,
    cus.DisplayName,
    cus.Reputation,
    cus.AnswerCount,
    cus.TotalAnswerScore,
    cus.AvgAnswerScore,
    cus.AcceptedAnswerCount,
    cus.TotalBadges,
    cus.GoldBadges,
    cus.SilverBadges,
    cus.BronzeBadges,
    cus.LatestVoteDate,
    cus.LatestVoteType,
    cus.RankByScore
FROM CombinedUserStats cus
WHERE cus.RankByScore <= 20
ORDER BY cus.RankByScore

UNION ALL

/* 8️⃣  Users who have never answered a <python> question but have earned at least one badge */
SELECT
    u.Id                              AS UserId,
    u.DisplayName,
    u.Reputation,
    0                                 AS AnswerCount,
    0                                 AS TotalAnswerScore,
    NULL                              AS AvgAnswerScore,
    0                                 AS AcceptedAnswerCount,
    b.TotalBadges,
    b.GoldBadges,
    b.SilverBadges,
    b.BronzeBadges,
    NULL                              AS LatestVoteDate,
    'None'                            AS LatestVoteType,
    NULL                              AS RankByScore
FROM Users u
JOIN (
    SELECT
        UserId,
        COUNT(*)                AS TotalBadges,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
) b ON b.UserId = u.Id
LEFT JOIN AnswerInfo a ON a.AnswerOwnerId = u.Id
WHERE a.AnswerOwnerId IS NULL               -- never answered a <python> question
  AND b.TotalBadges > 0
ORDER BY TotalBadges DESC, Reputation DESC
LIMIT 10;
