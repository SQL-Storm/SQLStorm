-- {"query": "3534.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2010} 

WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS UpVoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS DownVoteCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Votes v      ON v.UserId   = u.Id
    LEFT JOIN Badges b     ON b.UserId   = u.Id
    LEFT JOIN Posts p      ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

UserRecentActivity AS (
    SELECT
        u.Id,
        MAX(ph.CreationDate) AS LastEditOrClose
    FROM Users u
    LEFT JOIN PostHistory ph
        ON ph.UserId = u.Id
       AND ph.PostHistoryTypeId IN (4,5,6,10,11)      -- edits, close/reopen
    GROUP BY u.Id
),

Combined AS (
    SELECT
        us.Id,
        COALESCE(NULLIF(us.DisplayName, ''), 'Anonymous') AS SafeDisplayName,
        us.Reputation,
        us.UpVoteCount,
        us.DownVoteCount,
        us.BadgeCount,
        us.QuestionCount,
        us.AnswerCount,
        us.LastPostDate,
        ur.LastEditOrClose,
        CASE
            WHEN us.Reputation > 20000 THEN 'Elite'
            WHEN us.Reputation > 10000 THEN 'Pro'
            WHEN us.Reputation > 5000  THEN 'Active'
            ELSE 'Newbie'
        END AS ReputationBand
    FROM UserStats us
    LEFT JOIN UserRecentActivity ur ON ur.Id = us.Id
),

UserTopTags AS (
    SELECT
        p.OwnerUserId AS UserId,
        t.TagName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS rn
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(p.Tags, '><') AS tag
    ) AS dt
    JOIN Tags t ON t.TagName = dt.tag
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId, t.TagName
)

SELECT
    c.Id,
    c.SafeDisplayName,
    c.Reputation,
    c.UpVoteCount,
    c.DownVoteCount,
    c.BadgeCount,
    c.QuestionCount,
    c.AnswerCount,
    c.LastPostDate,
    c.LastEditOrClose,
    c.ReputationBand,
    STRING_AGG(DISTINCT utt.TagName, ', ') FILTER (WHERE utt.rn <= 5) AS TopTagsUsed
FROM Combined c
LEFT JOIN UserTopTags utt
    ON utt.UserId = c.Id AND utt.rn <= 5
WHERE c.ReputationBand <> 'Newbie'
GROUP BY
    c.Id, c.SafeDisplayName, c.Reputation, c.UpVoteCount, c.DownVoteCount,
    c.BadgeCount, c.QuestionCount, c.AnswerCount, c.LastPostDate,
    c.LastEditOrClose, c.ReputationBand
HAVING COUNT(DISTINCT utt.TagName) > 0
ORDER BY c.Reputation DESC
LIMIT 100

UNION ALL

SELECT
    NULL AS Id,
    'Aggregated Summary' AS SafeDisplayName,
    NULL AS Reputation,
    SUM(UpVoteCount)      AS UpVoteCount,
    SUM(DownVoteCount)    AS DownVoteCount,
    SUM(BadgeCount)       AS BadgeCount,
    SUM(QuestionCount)    AS QuestionCount,
    SUM(AnswerCount)      AS AnswerCount,
    MAX(LastPostDate)     AS LastPostDate,
    MAX(LastEditOrClose)  AS LastEditOrClose,
    NULL                  AS ReputationBand,
    NULL                  AS TopTagsUsed
FROM Combined
WHERE ReputationBand <> 'Newbie';
