WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END)                                   AS QuestionCount,
           COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END)                                   AS AnswerCount,
           SUM(CASE WHEN p.PostTypeId = 2 AND p.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END)    AS AcceptedAnswersGiven,
           MAX(p.CreationDate)                                                               AS LastPostDate,
           COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END),0)                           AS GoldBadges,
           COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END),0)                           AS SilverBadges,
           COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END),0)                           AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
    LEFT JOIN Posts q   ON q.Id = p.ParentId AND q.PostTypeId = 1
    LEFT JOIN Badges b  ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

TopUsers AS (
    SELECT us.Id,
           us.DisplayName,
           us.Reputation,
           us.QuestionCount,
           us.AnswerCount,
           us.AcceptedAnswersGiven,
           us.LastPostDate,
           us.GoldBadges,
           us.SilverBadges,
           us.BronzeBadges,
           ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.GoldBadges DESC, us.SilverBadges DESC) AS rn
    FROM UserStats us
    WHERE us.Reputation > 10000
),

TagInfo AS (
    SELECT t.TagName,
           t.Count                               AS TagUseCount,
           COALESCE(p.Title,'')                  AS TagExcerptTitle,
           REGEXP_REPLACE(COALESCE(p.Body,''), '<[^>]+>', '') AS CleanExcerpt
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
),

RecentVotes AS (
    SELECT v.PostId,
           vt.Name                                 AS VoteType,
           v.CreationDate,
           COALESCE(u.DisplayName,'<anonymous>')   AS VoterName,
           COALESCE(v.BountyAmount,0)              AS Bounty
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    LEFT JOIN Users u  ON u.Id = v.UserId
    WHERE v.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
),

AnswerStats AS (
    SELECT a.OwnerUserId,
           COUNT(*)                                            AS TotalAnswers,
           SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswers,
           AVG(a.Score)                                        AS AvgScore,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.Score) AS MedianScore
    FROM Posts a
    JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
    WHERE a.PostTypeId = 2
    GROUP BY a.OwnerUserId
),

Combined AS (
    SELECT tu.Id,
           tu.DisplayName,
           tu.Reputation,
           tu.QuestionCount,
           tu.AnswerCount,
           tu.GoldBadges,
           tu.SilverBadges,
           tu.BronzeBadges,
           COALESCE(asr.TotalAnswers,0)                AS TotalAnswersGiven,
           COALESCE(asr.AcceptedAnswers,0)             AS AcceptedAnswersGiven,
           asr.AvgScore,
           asr.MedianScore,
           tu.LastPostDate,
           ROW_NUMBER() OVER (PARTITION BY tu.Id ORDER BY tu.LastPostDate DESC) AS RecentPostRank,
           tu.rn
    FROM TopUsers tu
    LEFT JOIN AnswerStats asr ON asr.OwnerUserId = tu.Id
),

FinalSet AS (
    SELECT c.Id,
           c.DisplayName,
           c.Reputation,
           c.QuestionCount,
           c.AnswerCount,
           c.GoldBadges,
           c.SilverBadges,
           c.BronzeBadges,
           c.TotalAnswersGiven,
           c.AcceptedAnswersGiven,
           ROUND(CAST(c.AvgScore AS numeric),2)    AS AvgScore,
           c.MedianScore,
           (CAST(EXTRACT(YEAR FROM c.LastPostDate) AS varchar) || '-' ||
            LPAD(CAST(EXTRACT(MONTH FROM c.LastPostDate) AS varchar),2,'0') || '-' ||
            LPAD(CAST(EXTRACT(DAY FROM c.LastPostDate) AS varchar),2,'0')) AS LastPostDate,
           ti.TagName,
           ti.TagUseCount,
           ti.CleanExcerpt
    FROM Combined c
    LEFT JOIN Posts p ON p.OwnerUserId = c.Id AND p.CreationDate = c.LastPostDate
    LEFT JOIN LATERAL (
        SELECT ti.TagName, ti.TagUseCount, ti.CleanExcerpt
        FROM TagInfo ti
        WHERE POSITION(LOWER('#' || ti.TagName || '#') IN LOWER(COALESCE(p.Tags,''))) > 0
          AND p.OwnerUserId = c.Id
        ORDER BY ti.TagUseCount DESC
        LIMIT 1
    ) ti ON TRUE
    WHERE c.rn <= 50
)

SELECT *
FROM FinalSet

UNION ALL

SELECT NULL AS Id,
       '--- Recent Votes Summary ---' AS DisplayName,
       NULL AS Reputation,
       NULL AS QuestionCount,
       NULL AS AnswerCount,
       NULL AS GoldBadges,
       NULL AS SilverBadges,
       NULL AS BronzeBadges,
       NULL AS TotalAnswersGiven,
       NULL AS AcceptedAnswersGiven,
       NULL AS AvgScore,
       NULL AS MedianScore,
       NULL AS LastPostDate,
       NULL AS TagName,
       NULL AS TagUseCount,
       NULL AS CleanExcerpt
FROM (
    SELECT COUNT(*)                                    AS TotalVotes,
           SUM(CASE WHEN VoteType = 'UpMod'   THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN VoteType = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
           SUM(Bounty)                                AS TotalBounty
    FROM RecentVotes
) sv
ORDER BY Reputation DESC NULLS LAST, GoldBadges DESC NULLS LAST
LIMIT 100;