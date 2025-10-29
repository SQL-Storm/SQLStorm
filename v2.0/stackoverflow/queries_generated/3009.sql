-- {"query": "3009.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1894} 

WITH TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
),
UserStats AS (
    SELECT
        u.Id                                    AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(COALESCE(v.UpVotes, 0) - COALESCE(v.DownVotes, 0)) AS VoteScore,
        MAX(p.CreationDate)                     AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            pv.PostId,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes pv
        JOIN VoteTypes vt ON vt.Id = pv.VoteTypeId
        GROUP BY pv.PostId
    ) v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
LatestClosedPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        ph.Comment                               AS CloseReason,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                           ORDER BY p.ClosedDate DESC NULLS LAST) AS rn
    FROM Posts p
    JOIN PostHistory ph
      ON ph.PostId = p.Id
     AND ph.PostHistoryTypeId = 10               -- close reason stored here
    WHERE p.ClosedDate IS NOT NULL
)
SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.VoteScore,
    COALESCE(lcp.Title, 'No closed posts')   AS LatestClosedTitle,
    COALESCE(lcp.CloseReason, 'N/A')         AS CloseReason,
    CASE
        WHEN us.QuestionCount = 0 THEN NULL
        ELSE ROUND(us.AnswerCount::numeric / us.QuestionCount, 2)
    END                                      AS AnswerPerQuestion,
    STRING_AGG(DISTINCT tt.TagName, ', ') FILTER (WHERE tt.rn <= 5) AS Top5Tags,
    b.Name                                   AS GoldBadge,
    COALESCE(b.Class, 3)                     AS BadgeClass
FROM UserStats us
LEFT JOIN LATERAL (
    SELECT *
    FROM LatestClosedPosts lcp
    WHERE lcp.OwnerUserId = us.UserId
      AND lcp.rn = 1
) lcp ON TRUE
LEFT JOIN TopTags tt ON TRUE
LEFT JOIN Badges b
       ON b.UserId = us.UserId
      AND b.Class = 1                            -- gold badges only
GROUP BY
    us.UserId, us.DisplayName, us.Reputation,
    us.QuestionCount, us.AnswerCount, us.VoteScore,
    lcp.Title, lcp.CloseReason, b.Name, b.Class
HAVING COUNT(*) FILTER (WHERE tt.rn <= 5) > 0

UNION ALL

SELECT
    NULL AS UserId,
    NULL AS DisplayName,
    NULL AS Reputation,
    NULL AS QuestionCount,
    NULL AS AnswerCount,
    NULL AS VoteScore,
    NULL AS LatestClosedTitle,
    NULL AS CloseReason,
    NULL AS AnswerPerQuestion,
    STRING_AGG(DISTINCT tt.TagName, ', ')      AS AllTopTags,
    NULL AS GoldBadge,
    NULL AS BadgeClass
FROM TopTags tt
WHERE tt.rn <= 10;
