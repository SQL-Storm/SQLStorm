WITH QuestionStats AS (
    SELECT
        OwnerUserId               AS UserId,
        COUNT(*)                  AS QCount,
        SUM(COALESCE(Score,0))    AS QScoreSum,
        MAX(CreationDate)         AS LastQuestionDate,
        AVG(AnswerCount)          AS AvgAnswersPerQuestion,
        SUM(COALESCE(FavoriteCount,0)) AS QFavSum,
        (
          SELECT STRING_AGG(DISTINCT TRIM(BOTH '<>' FROM t.tag), ',')
          FROM (
            SELECT UNNEST(STRING_TO_ARRAY(Tags, '><')) AS tag
          ) AS t
        ) AS AllTags
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY OwnerUserId, Tags
),
AnswerStats AS (
    SELECT
        OwnerUserId                           AS UserId,
        COUNT(*)                              AS ACount,
        SUM(COALESCE(Score,0))                AS AScoreSum,
        MAX(CreationDate)                     AS LastAnswerDate,
        SUM(CASE WHEN Id = COALESCE(p.AcceptedAnswerId,0) THEN 1 ELSE 0 END) AS AcceptedAnswers
    FROM Posts p
    WHERE PostTypeId = 2
    GROUP BY OwnerUserId
),
BadgeStats AS (
    SELECT
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(*)                               AS TotalBadges
    FROM Badges
    GROUP BY UserId
),
VoteStats AS (
    SELECT
        PostId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
),
UserActivity AS (
    SELECT
        u.Id                                     AS Id,
        COALESCE(q.QCount,0)                     AS QCount,
        COALESCE(a.ACount,0)                     AS ACount,
        COALESCE(b.TotalBadges,0)                AS BadgeCount,
        GREATEST(
            COALESCE(q.LastQuestionDate, TIMESTAMP '1970-01-01'),
            COALESCE(a.LastAnswerDate, TIMESTAMP '1970-01-01'),
            u.LastAccessDate
        )                                        AS LastActivity
    FROM Users u
    LEFT JOIN QuestionStats q ON q.UserId = u.Id
    LEFT JOIN AnswerStats   a ON a.UserId = u.Id
    LEFT JOIN BadgeStats    b ON b.UserId = u.Id
)
SELECT
    ua.Id,
    u.DisplayName,
    u.Reputation,
    ua.QCount,
    ua.ACount,
    ua.BadgeCount,
    ua.LastActivity,
    COALESCE(q.QScoreSum,0) + COALESCE(a.AScoreSum,0)               AS TotalScore,
    RANK() OVER (ORDER BY (u.Reputation + COALESCE(q.QScoreSum,0) + COALESCE(a.AScoreSum,0)) DESC) AS ReputationScoreRank,
    CASE
        WHEN ua.QCount = 0 AND ua.ACount = 0 THEN 'Inactive'
        WHEN ua.QCount > ua.ACount                THEN 'Questioner'
        ELSE                                      'Answerer'
    END                                                            AS PrimaryRole,
    COALESCE(q.AllTags,'')                                         AS TagsUsed,
    COALESCE(v.UpVotes,0) - COALESCE(v.DownVotes,0)                 AS NetPostVotes
FROM UserActivity ua
JOIN Users u ON u.Id = ua.Id
LEFT JOIN QuestionStats q ON q.UserId = ua.Id
LEFT JOIN AnswerStats   a ON a.UserId = ua.Id
LEFT JOIN (
    SELECT ua_inner.Id AS ua_id, vs.UpVotes, vs.DownVotes FROM Users ua_inner
    JOIN LATERAL (
      SELECT vs2.UpVotes, vs2.DownVotes
      FROM Posts p
      LEFT JOIN VoteStats vs2 ON vs2.PostId = p.Id
      WHERE p.OwnerUserId = ua_inner.Id
      ORDER BY p.CreationDate DESC
      LIMIT 1
    ) vs ON true
) v ON v.ua_id = ua.Id
WHERE ua.LastActivity > (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR)

UNION ALL

SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    0                               AS QCount,
    0                               AS ACount,
    0                               AS BadgeCount,
    u.LastAccessDate                AS LastActivity,
    0                               AS TotalScore,
    NULL                            AS ReputationScoreRank,
    'New'                           AS PrimaryRole,
    ''                              AS TagsUsed,
    0                               AS NetPostVotes
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
  AND u.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '6' MONTH)

ORDER BY ReputationScoreRank NULLS LAST, TotalScore DESC;