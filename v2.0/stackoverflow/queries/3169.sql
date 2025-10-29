WITH PostAgg AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAccepted,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    GROUP BY p.OwnerUserId
),
BadgeAgg AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 1) AS GoldBadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
VoteAgg AS (
    SELECT
        v.UserId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesCast,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesCast,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    GROUP BY v.UserId
),
TagStats AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS QuestionCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS ClosedCount,
        ROUND(100.0 * SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) /
              NULLIF(COUNT(p.Id),0),2) AS ClosedPct
    FROM Tags t
    JOIN Posts p
      ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%' AND p.PostTypeId = 1
    LEFT JOIN PostHistory ph
      ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 100
),
UserMetrics AS (
    SELECT
        u.Id,
        COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
        u.Reputation,
        COALESCE(pa.QuestionCount,0) AS QuestionCount,
        COALESCE(pa.AnswerCount,0) AS AnswerCount,
        COALESCE(pa.AvgQuestionScore,0) AS AvgQuestionScore,
        COALESCE(pa.AvgAnswerScore,0) AS AvgAnswerScore,
        COALESCE(ba.GoldBadges,0) AS GoldBadges,
        COALESCE(ba.SilverBadges,0) AS SilverBadges,
        COALESCE(ba.BronzeBadges,0) AS BronzeBadges,
        COALESCE(va.UpVotesCast,0) AS UpVotesCast,
        COALESCE(va.DownVotesCast,0) AS DownVotesCast,
        GREATEST(COALESCE(pa.LastPostDate, TIMESTAMP '1970-01-01'), COALESCE(va.LastVoteDate, TIMESTAMP '1970-01-01')) AS LastActivity,
        CASE
            WHEN u.Reputation > 20000 THEN 'Legendary'
            WHEN u.Reputation > 10000 THEN 'Trusted'
            WHEN u.Reputation > 2000  THEN 'Established'
            ELSE 'Newbie'
        END AS ReputationTier,
        ROW_NUMBER() OVER (ORDER BY (COALESCE(pa.QuestionCount,0)*2 +
                                     COALESCE(pa.AnswerCount,0) +
                                     COALESCE(ba.GoldBadges,0)*5) DESC) AS RankByContribution,
        (SELECT COUNT(*)
         FROM Posts q
         WHERE q.OwnerUserId = u.Id
           AND q.PostTypeId = 1
           AND EXISTS (SELECT 1 FROM Posts a
                       WHERE a.ParentId = q.Id
                         AND a.OwnerUserId = u.Id
                         AND a.Id = q.AcceptedAnswerId)
        ) AS SelfAcceptedAnswers
    FROM Users u
    LEFT JOIN PostAgg pa ON pa.UserId = u.Id
    LEFT JOIN BadgeAgg ba ON ba.UserId = u.Id
    LEFT JOIN VoteAgg va ON va.UserId = u.Id
),
TopTagContributions AS (
    SELECT
        um.Id AS UserId,
        STRING_AGG(DISTINCT t.TagName, ', ') FILTER (WHERE t.TagName IS NOT NULL) AS TopTags
    FROM UserMetrics um
    JOIN Posts p ON p.OwnerUserId = um.Id AND p.PostTypeId = 1
    JOIN (
      SELECT p2.Id AS PostId,
             TRIM(SUBSTR(p2.Tags, pos, pos_end - pos - 1)) AS tagname
      FROM Posts p2
      CROSS JOIN LATERAL (
        SELECT seq.pos, seq.pos_end
        FROM (
          SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
          UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
          UNION ALL SELECT 11 UNION ALL SELECT 12 UNION ALL SELECT 13 UNION ALL SELECT 14 UNION ALL SELECT 15
        ) AS times(n)
        CROSS JOIN LATERAL (
          SELECT
            CASE
              WHEN times.n = 1 THEN POSITION('<' IN p2.Tags)
              WHEN times.n = 2 THEN NULLIF(POSITION('<' IN SUBSTR(p2.Tags, POSITION('<' IN p2.Tags) + 1)), 0) + POSITION('<' IN p2.Tags)
              WHEN times.n = 3 THEN (
                WITH c1 AS (SELECT POSITION('<' IN p2.Tags) AS p1)
                SELECT NULLIF(POSITION('<' IN SUBSTR(p2.Tags, p1 + 1)),0) + p1 FROM c1
              )
              ELSE NULL
            END AS pos,
            CASE
              WHEN times.n = 1 THEN POSITION('>' IN p2.Tags)
              WHEN times.n = 2 THEN NULLIF(POSITION('>' IN SUBSTR(p2.Tags, POSITION('>' IN p2.Tags) + 1)), 0) + POSITION('>' IN p2.Tags)
              ELSE NULL
            END AS pos_end
        ) AS seq(pos, pos_end)
        WHERE seq.pos IS NOT NULL AND seq.pos > 0 AND seq.pos_end IS NOT NULL AND seq.pos_end > seq.pos
      ) AS instr_sub
      WHERE p2.Tags IS NOT NULL
    ) split ON split.PostId = p.Id
    JOIN Tags t ON t.TagName = split.tagname
    GROUP BY um.Id
),
MainResults AS (
SELECT
    um.Id,
    um.DisplayName,
    um.Reputation,
    um.QuestionCount,
    um.AnswerCount,
    ROUND(CAST(um.AvgQuestionScore AS numeric),2) AS AvgQuestionScore,
    ROUND(CAST(um.AvgAnswerScore AS numeric),2) AS AvgAnswerScore,
    um.GoldBadges,
    um.SilverBadges,
    um.BronzeBadges,
    um.UpVotesCast,
    um.DownVotesCast,
    um.LastActivity,
    um.ReputationTier,
    um.RankByContribution,
    um.SelfAcceptedAnswers,
    COALESCE(ttc.TopTags,'none') AS TopTags,
    CASE
        WHEN um.QuestionCount = 0 THEN NULL
        ELSE CAST(um.AnswerCount AS double precision) / um.QuestionCount
    END AS AnswerToQuestionRatio
FROM UserMetrics um
LEFT JOIN TopTagContributions ttc ON ttc.UserId = um.Id
WHERE um.RankByContribution <= 100
)
SELECT *
FROM MainResults
UNION ALL
SELECT
    -1 AS Id,
    'Community' AS DisplayName,
    NULL AS Reputation,
    NULL AS QuestionCount,
    NULL AS AnswerCount,
    NULL AS AvgQuestionScore,
    NULL AS AvgAnswerScore,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    NULL AS UpVotesCast,
    NULL AS DownVotesCast,
    NULL AS LastActivity,
    'Community' AS ReputationTier,
    NULL AS RankByContribution,
    NULL AS SelfAcceptedAnswers,
    NULL AS TopTags,
    NULL AS AnswerToQuestionRatio
WHERE EXISTS (SELECT 1 FROM Posts WHERE OwnerUserId = -1)
ORDER BY RankByContribution NULLS LAST
LIMIT 101;