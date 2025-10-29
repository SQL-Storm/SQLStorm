-- {"query": "3063.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1961} 

WITH UserPostAgg AS (
    SELECT 
        u.Id               AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id)                        FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id)                        FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COALESCE(SUM(p.Score), 0)                         AS TotalPostScore,
        MAX(p.CreationDate)                               AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

BadgeAgg AS (
    SELECT 
        b.UserId,
        COUNT(*)                                          AS BadgeTotal,
        COUNT(*) FILTER (WHERE b.Class = 1)               AS GoldBadge,
        COUNT(*) FILTER (WHERE b.Class = 2)               AS SilverBadge,
        COUNT(*) FILTER (WHERE b.Class = 3)               AS BronzeBadge,
        SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END)   AS TagBasedBadge
    FROM Badges b
    GROUP BY b.UserId
),

TagStats AS (
    SELECT 
        t.TagName,
        t.Count                                           AS TagUseCount,
        COALESCE(e.Id, 0)                                 AS ExcerptPostId,
        COALESCE(w.Id, 0)                                 AS WikiPostId
    FROM Tags t
    LEFT JOIN Posts e ON e.Id = t.ExcerptPostId
    LEFT JOIN Posts w ON w.Id = t.WikiPostId
),

RecentVotes AS (
    SELECT 
        v.PostId,
        MAX(v.CreationDate)                               AS LastVoteDate,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2)          AS UpVotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3)          AS DownVotes
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
        COALESCE(ba.BadgeTotal, 0)                        AS BadgeTotal,
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
WHERE u.LastAccessDate < CURRENT_DATE - INTERVAL '1 year'
  AND NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)

ORDER BY RankScore NULLS LAST, Reputation DESC
LIMIT 500;
