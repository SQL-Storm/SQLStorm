WITH UserPostAgg AS (
    SELECT 
        u.Id               AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END)    AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END)    AS AnswerCount,
        COALESCE(SUM(p.Score), 0)                       AS TotalPostScore,
        MAX(p.CreationDate)                             AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

BadgeAgg AS (
    SELECT 
        b.UserId,
        COUNT(*)                                        AS BadgeTotal,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END)         AS GoldBadge,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END)         AS SilverBadge,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END)         AS BronzeBadge,
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END)   AS TagBasedBadge
    FROM Badges b
    GROUP BY b.UserId
),

TagStats AS (
    SELECT 
        t.TagName,
        t.Count                                         AS TagUseCount,
        COALESCE(e.Id, 0)                               AS ExcerptPostId,
        COALESCE(w.Id, 0)                               AS WikiPostId
    FROM Tags t
    LEFT JOIN Posts e ON e.Id = t.ExcerptPostId
    LEFT JOIN Posts w ON w.Id = t.WikiPostId
),

RecentVotes AS (
    SELECT 
        v.PostId,
        MAX(v.CreationDate)                             AS LastVoteDate,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END)    AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END)    AS DownVotes
    FROM Votes v
    GROUP BY v.PostId
),

TopUsers AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.TotalPostScore,
        COALESCE(ba.BadgeTotal, 0)                      AS BadgeTotal,
        ROW_NUMBER() OVER (ORDER BY ua.TotalPostScore DESC, ua.Reputation DESC) AS RankScore
    FROM UserPostAgg ua
    LEFT JOIN BadgeAgg ba ON ba.UserId = ua.UserId
    WHERE ua.Reputation > 1000
      AND ua.AnswerCount > 10
)

SELECT 
    tu.RankScore,
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.TotalPostScore,
    tu.BadgeTotal,
    CASE 
        WHEN tu.RankScore <= 10  THEN 'Top 10'
        WHEN tu.RankScore <= 100 THEN 'Top 100'
        ELSE 'Other'
    END                                          AS RankCategory,
    COALESCE((
        SELECT STRING_AGG(DISTINCT pt.Tags, ',')
        FROM Posts pt
        WHERE pt.OwnerUserId = tu.UserId
          AND pt.PostTypeId = 1
          AND pt.Tags IS NOT NULL
    ), '')                                     AS QuestionTags,
    (SELECT COUNT(*) 
     FROM Comments c 
     WHERE c.UserId = tu.UserId 
       AND c.Score > 0)                        AS PositiveCommentCount,
    (SELECT COUNT(*) 
     FROM PostHistory ph 
     WHERE ph.UserId = tu.UserId 
       AND ph.PostHistoryTypeId = 10 
       AND ph.Comment IS NOT NULL)            AS CloseVotesCast
FROM TopUsers tu
WHERE tu.RankScore <= 200

UNION ALL

SELECT 
    NULL                                      AS RankScore,
    u.Id                                      AS UserId,
    u.DisplayName,
    u.Reputation,
    0                                         AS QuestionCount,
    0                                         AS AnswerCount,
    0                                         AS TotalPostScore,
    0                                         AS BadgeTotal,
    'Inactive'                                AS RankCategory,
    NULL                                      AS QuestionTags,
    0                                         AS PositiveCommentCount,
    0                                         AS CloseVotesCast
FROM Users u
WHERE u.LastAccessDate < CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
  AND NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)

ORDER BY RankScore NULLS LAST, Reputation DESC
LIMIT 500;