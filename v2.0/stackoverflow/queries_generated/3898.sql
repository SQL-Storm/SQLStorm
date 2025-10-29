-- {"query": "3898.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2065} 

WITH
    UserStats AS (
        SELECT
            u.Id                        AS UserId,
            u.DisplayName,
            u.Reputation,
            COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
            COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            COALESCE(SUM(v.Score), 0)   AS TotalPostScore,
            MAX(u.LastAccessDate)       AS LastSeen
        FROM Users u
        LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
        LEFT JOIN Votes v   ON v.PostId = p.Id AND v.VoteTypeId = 2
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),
    TopBadges AS (
        SELECT
            b.UserId,
            STRING_AGG(b.Name, ', ' ORDER BY b.Class) AS BadgesList,
            COUNT(*)                                 AS BadgeCount,
            ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Class) AS BadgeRank
        FROM Badges b
        GROUP BY b.UserId
    ),
    RecentComments AS (
        SELECT
            c.PostId,
            STRING_AGG(CONCAT(c.UserId, ':', LEFT(c.Text, 30)), '; ') AS CommentSnippets,
            MAX(c.CreationDate)                                     AS LatestComment
        FROM Comments c
        WHERE c.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
        GROUP BY c.PostId
    ),
    TagInfo AS (
        SELECT
            t.TagName,
            t.Count                               AS TagUseCount,
            COALESCE(p.Title, '')                 AS TagExcerptTitle,
            ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
        FROM Tags t
        LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
        WHERE t.TagName IS NOT NULL
    )
SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalPostScore,
    tb.BadgesList,
    tb.BadgeCount,
    rc.CommentSnippets,
    rc.LatestComment,
    ti.TagName,
    ti.TagUseCount,
    ti.TagRank,
    CASE
        WHEN us.Reputation > 20000 THEN 'Elite'
        WHEN us.Reputation > 10000 THEN 'Pro'
        WHEN us.Reputation > 5000  THEN 'Experienced'
        ELSE 'Novice'
    END                                            AS ReputationTier,
    COALESCE(NULLIF(us.LastSeen, '1970-01-01'), CURRENT_TIMESTAMP) AS EffectiveLastSeen,
    (
        SELECT COUNT(*)
        FROM Posts p2
        WHERE p2.OwnerUserId = us.UserId
          AND p2.CreationDate > us.LastSeen
          AND p2.PostTypeId = 1
    )                                              AS NewQuestionsSinceLastSeen,
    (
        SELECT COUNT(*)
        FROM Votes v2
        WHERE v2.UserId = us.UserId
          AND v2.VoteTypeId = 2
          AND v2.CreationDate > us.LastSeen
    )                                              AS RecentUpVotesGiven
FROM UserStats us
LEFT JOIN TopBadges tb
       ON tb.UserId = us.UserId AND tb.BadgeRank = 1
LEFT JOIN RecentComments rc
       ON rc.PostId = (
            SELECT p3.Id
            FROM Posts p3
            WHERE p3.OwnerUserId = us.UserId
            ORDER BY p3.CreationDate DESC
            LIMIT 1
       )
LEFT JOIN TagInfo ti
       ON ti.TagRank <= 5
WHERE us.Reputation IS NOT NULL
  AND (us.QuestionCount + us.AnswerCount) > 0
  AND EXISTS (
        SELECT 1
        FROM Posts p4
        WHERE p4.OwnerUserId = us.UserId
          AND p4.Score < 0
          AND p4.PostTypeId = 2
      )
UNION ALL
SELECT
    NULL,
    'Aggregated Summary',
    NULL,
    SUM(us.QuestionCount),
    SUM(us.AnswerCount),
    SUM(us.TotalPostScore),
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    'Summary',
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM UserStats us
WHERE us.Reputation > 0
ORDER BY ReputationTier DESC NULLS LAST, us.Reputation DESC
LIMIT 100;
