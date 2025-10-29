-- {"query": "3227.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2439} 

WITH
    TagUsage AS (
        SELECT
            t.TagName,
            t.Count,
            ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
        FROM Tags t
        WHERE t.IsModeratorOnly = 0
    ),
    RecentQuestions AS (
        SELECT
            p.Id,
            p.Title,
            p.CreationDate,
            p.OwnerUserId,
            COALESCE(p.Tags, '') AS RawTags,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_user
        FROM Posts p
        WHERE p.PostTypeId = 1                         -- Question
          AND p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    ),
    UserReputation AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            u.CreationDate,
            COALESCE(u.Location, 'Unknown') AS Location,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteGiven,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteGiven
        FROM Users u
        LEFT JOIN Votes v ON v.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
    ),
    QuestionScoreStats AS (
        SELECT
            p.Id,
            p.Score,
            AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgScoreByOwner,
            PERCENT_RANK() OVER (ORDER BY p.Score DESC) AS ScorePercentile
        FROM Posts p
        WHERE p.PostTypeId = 1
    )
SELECT
    rq.Id AS QuestionId,
    rq.Title,
    rq.CreationDate,
    ur.DisplayName,
    ur.Reputation,
    ur.Location,
    qs.Score,
    qs.AvgScoreByOwner,
    qs.ScorePercentile,
    COALESCE(uac.GoldBadgeCount,0) AS GoldBadgeCount,
    COALESCE(uac.SilverBadgeCount,0) AS SilverBadgeCount,
    COALESCE(uac.BronzeBadgeCount,0) AS BronzeBadgeCount,
    COALESCE(vu.UpVotes,0) AS TotalUpVotes,
    COALESCE(vu.DownVotes,0) AS TotalDownVotes,
    COALESCE(tu.TagName,'<none>') AS TopTag,
    CASE
        WHEN rq.RawTags LIKE '%<java>%'
            THEN 'Java'
        WHEN rq.RawTags LIKE '%<c#>%'
            THEN 'C#'
        ELSE 'Other'
    END AS PrimaryLanguage,
    (SELECT COUNT(*) FROM Posts a WHERE a.PostTypeId = 2 AND a.ParentId = rq.Id) AS AnswerCount,
    EXISTS (
        SELECT 1 FROM Posts a
        WHERE a.PostTypeId = 2
          AND a.ParentId = rq.Id
          AND a.Id = p.AcceptedAnswerId
    ) AS HasAcceptedAnswer
FROM RecentQuestions rq
LEFT JOIN UserReputation ur ON ur.Id = rq.OwnerUserId
LEFT JOIN QuestionScoreStats qs ON qs.Id = rq.Id
LEFT JOIN (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
    FROM Badges b
    GROUP BY b.UserId
) uac ON uac.UserId = ur.Id
LEFT JOIN (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    GROUP BY v.PostId
) vu ON vu.PostId = rq.Id
LEFT JOIN TagUsage tu ON tu.rn = 1
WHERE rq.rn_user = 1
  AND (ur.Reputation IS NULL OR ur.Reputation > 1000)
  AND (vu.UpVotes IS NULL OR vu.UpVotes >= 5)

UNION ALL

SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    u.DisplayName,
    u.Reputation,
    COALESCE(u.Location,'Unknown') AS Location,
    p.Score,
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
    NULL,
    NULL
FROM Posts p
JOIN Users u ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 1
  AND p.CreationDate < CURRENT_DATE - INTERVAL '1 year'
  AND NOT EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2)
ORDER BY QuestionId DESC NULLS LAST
LIMIT 100;
