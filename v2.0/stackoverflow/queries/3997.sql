-- {"query": "3997.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1710} 
WITH UserStats AS (
    SELECT 
        u.Id                                      AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)  AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)  AS AnswerCount,
        SUM(COALESCE(v.UpVotes,0) - COALESCE(v.DownVotes,0)) AS NetScore,
        MAX(p.CreationDate)                      AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT 
            pv.PostId,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes pv
        JOIN VoteTypes vt
            ON vt.Id = pv.VoteTypeId
        GROUP BY pv.PostId
    ) v
        ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagActivity AS (
    SELECT 
        t.TagName,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 2) AS Edits,
        COUNT(*) FILTER (WHERE pl.LinkTypeId = 3)        AS DuplicateLinks,
        ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC)      AS TagRank
    FROM Tags t
    LEFT JOIN PostHistory ph
        ON ph.PostId = t.ExcerptPostId OR ph.PostId = t.WikiPostId
    LEFT JOIN PostLinks pl
        ON pl.PostId = t.ExcerptPostId OR pl.PostId = t.WikiPostId
    GROUP BY t.TagName
),
RecentBadges AS (
    SELECT 
        b.UserId,
        STRING_AGG(b.Name, ', ') FILTER (WHERE b.Class = 1) AS GoldBadges,
        MAX(b.Date)                                            AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
)

SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.NetScore,
    us.LastPostDate,
    rb.GoldBadges,
    rb.LastBadgeDate,
    ta.TagName,
    ta.Edits,
    ta.DuplicateLinks,
    ta.TagRank
FROM UserStats us
LEFT JOIN RecentBadges rb
    ON rb.UserId = us.UserId
LEFT JOIN LATERAL (
    SELECT 
        ta2.TagName,
        ta2.Edits,
        ta2.DuplicateLinks,
        ta2.TagRank
    FROM TagActivity ta2
    WHERE ta2.TagRank <= 5
    ORDER BY ta2.TagRank
    LIMIT 1
) ta ON TRUE
WHERE us.Reputation > 10000
  AND (us.QuestionCount + us.AnswerCount) > 100
  AND (us.LastPostDate IS NULL OR us.LastPostDate > cast('2024-10-01' as date) - INTERVAL '1 year')

UNION ALL

SELECT
    NULL AS UserId,
    NULL AS DisplayName,
    NULL AS Reputation,
    NULL AS QuestionCount,
    NULL AS AnswerCount,
    NULL AS NetScore,
    NULL AS LastPostDate,
    NULL AS GoldBadges,
    NULL AS LastBadgeDate,
    t.TagName,
    t.Edits,
    t.DuplicateLinks,
    t.TagRank
FROM TagActivity t
WHERE t.TagRank <= 10

ORDER BY Reputation DESC NULLS LAST, TagRank ASC NULLS LAST
LIMIT 100;