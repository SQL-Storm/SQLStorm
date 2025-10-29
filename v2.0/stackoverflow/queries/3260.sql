-- {"query": "3260.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1573}
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopTags AS (
    SELECT 
        t.TagName,
        COUNT(ph.Id) AS UsageCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(ph.Id) DESC) AS rn
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 5
    GROUP BY t.TagName
),
UserBadgeScore AS (
    SELECT 
        b.UserId,
        SUM(CASE b.Class WHEN 1 THEN 100 WHEN 2 THEN 50 ELSE 10 END) AS BadgeScore
    FROM Badges b
    GROUP BY b.UserId
),
RecentClosedQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        ph.CreationDate AS ClosedDate,
        COALESCE(NULLIF(ph.Comment, ''), 'Unknown') AS CloseReason
    FROM Posts p
    JOIN PostHistory ph 
        ON ph.PostId = p.Id 
       AND ph.PostHistoryTypeId = 10
    WHERE p.PostTypeId = 1
      AND ph.CreationDate > (DATE '2024-10-01' - INTERVAL '30' DAY)
)
SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.UpVotesGiven,
    us.DownVotesGiven,
    COALESCE(ub.BadgeScore, 0) AS BadgeScore,
    us.LastPostDate,
    tt.TagName,
    tt.UsageCount,
    rc.Title AS RecentClosedTitle,
    rc.CloseReason,
    CASE
        WHEN us.Reputation > 20000 THEN 'Power User'
        WHEN us.Reputation > 10000 THEN 'Experienced'
        WHEN us.Reputation > 1000  THEN 'Active'
        ELSE 'Newbie'
    END AS ReputationBand,
    (SELECT COUNT(*) 
       FROM Comments c 
      WHERE c.UserId = us.Id 
        AND c.Score > 5) AS HighScoreComments,
    (SELECT MAX(v2.CreationDate) 
       FROM Votes v2 
      WHERE v2.UserId = us.Id 
        AND v2.VoteTypeId = 2) AS LastUpvoteGiven
FROM UserStats us
LEFT JOIN UserBadgeScore ub ON ub.UserId = us.Id
LEFT JOIN TopTags tt ON tt.rn <= 5
LEFT JOIN RecentClosedQuestions rc ON rc.Id = us.Id
WHERE (us.QuestionCount + us.AnswerCount) > 0

UNION ALL

SELECT 
    CAST(NULL AS BIGINT)      AS Id,
    CAST(NULL AS TEXT)        AS DisplayName,
    CAST(NULL AS BIGINT)      AS Reputation,
    CAST(NULL AS BIGINT)      AS QuestionCount,
    CAST(NULL AS BIGINT)      AS AnswerCount,
    CAST(NULL AS BIGINT)      AS UpVotesGiven,
    CAST(NULL AS BIGINT)      AS DownVotesGiven,
    CAST(NULL AS BIGINT)      AS BadgeScore,
    CAST(NULL AS TIMESTAMP)   AS LastPostDate,
    CAST(NULL AS TEXT)        AS TagName,
    CAST(NULL AS BIGINT)      AS UsageCount,
    CAST(NULL AS TEXT)        AS RecentClosedTitle,
    CAST(NULL AS TEXT)        AS CloseReason,
    CAST(NULL AS TEXT)        AS ReputationBand,
    CAST(NULL AS BIGINT)      AS HighScoreComments,
    CAST(NULL AS TIMESTAMP)   AS LastUpvoteGiven
FROM (SELECT 1) AS dummy
WHERE NOT EXISTS (SELECT 1 FROM Users)
LIMIT 100;