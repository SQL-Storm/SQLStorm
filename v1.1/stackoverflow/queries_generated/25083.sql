-- {"query": "25083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1873} 

WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)               AS NetVotes,
        COUNT(b.Id) FILTER (WHERE b.Class = 1)                        AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2)                        AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3)                        AS BronzeBadges,
        MAX(p.CreationDate)                                          AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b   ON b.UserId = u.Id
    LEFT JOIN Posts  p   ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),
TagStats AS (
    SELECT
        t.TagName,
        t.Count                                              AS TagUseCount,
        COALESCE(SUM(p.Score),0)                              AS TotalScore,
        MAX(p.CreationDate)                                   AS LatestPostDate,
        STRING_AGG(DISTINCT u.DisplayName, ', ') 
            FILTER (WHERE u.Id IS NOT NULL)                  AS TopContributors
    FROM Tags t
    LEFT JOIN Posts p 
        ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    LEFT JOIN Users u 
        ON u.Id = p.OwnerUserId
    GROUP BY t.TagName, t.Count
),
RecentClosedQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        ph.CreationDate                                      AS ClosedDate,
        CAST(ph.Comment AS INT)                              AS CloseReasonId,
        ROW_NUMBER() OVER (PARTITION BY p.Id 
                           ORDER BY ph.CreationDate DESC)    AS rn
    FROM Posts p
    JOIN PostHistory ph ON ph.PostId = p.Id
    WHERE p.PostTypeId = 1                -- only questions
      AND ph.PostHistoryTypeId = 10       -- closed
)
SELECT
    us.Id                                 AS UserId,
    us.DisplayName,
    us.Reputation,
    us.NetVotes,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.LastPostDate,
    ts.TagName,
    ts.TagUseCount,
    ts.TotalScore,
    ts.LatestPostDate,
    ts.TopContributors,
    rcq.Title                             AS ClosedQuestionTitle,
    rcq.ClosedDate,
    COALESCE(crt.Name, 'Unknown')         AS CloseReason,
    CASE WHEN us.Reputation > 20000 THEN 'Veteran' ELSE 'Regular' END AS UserTier
FROM UserStats us
LEFT JOIN TagStats ts 
       ON ts.TagName = ANY(string_to_array(us.DisplayName, ' '))
LEFT JOIN (
    SELECT Id, Title, ClosedDate, CloseReasonId
    FROM RecentClosedQuestions
    WHERE rn = 1
) rcq 
       ON rcq.Id = us.Id
LEFT JOIN CloseReasonTypes crt 
       ON crt.Id = rcq.CloseReasonId
WHERE (us.Reputation IS NOT NULL AND us.Reputation > 1000)
   OR (ts.TagUseCount > 5000)

UNION ALL

SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    CASE 
        WHEN v.VoteTypeId = 2 THEN 'Upvote'
        WHEN v.VoteTypeId = 3 THEN 'Downvote'
        ELSE 'Other' 
    END AS VoteKind
FROM Users u
JOIN Votes v ON v.UserId = u.Id
WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
  AND v.VoteTypeId IN (2,3)
  AND NOT EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
          AND p.CreationDate > v.CreationDate
      )
ORDER BY UserId NULLS LAST, Reputation DESC
LIMIT 100;
