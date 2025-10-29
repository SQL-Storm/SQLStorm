WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(qc.QuestionCount, 0)      AS QuestionCount,
        COALESCE(ac.AnswerCount, 0)        AS AnswerCount,
        COALESCE(bc.GoldCount, 0)          AS GoldBadges,
        COALESCE(bc.SilverCount, 0)        AS SilverBadges,
        COALESCE(bc.BronzeCount, 0)        AS BronzeBadges,
        (
            SELECT MAX(p.CreationDate) 
            FROM Posts p 
            WHERE p.OwnerUserId = u.Id
        )                                 AS LastPostDate
    FROM Users u
    LEFT JOIN (
        SELECT OwnerUserId,
               SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
               SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
        FROM Posts
        GROUP BY OwnerUserId
    ) qc ON qc.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT OwnerUserId,
               SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
        FROM Posts
        GROUP BY OwnerUserId
    ) ac ON ac.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT UserId,
               SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
               SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
               SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeCount
        FROM Badges
        GROUP BY UserId
    ) bc ON bc.UserId = u.Id
),
TopTags AS (
    SELECT 
        TagName,
        Count,
        ROW_NUMBER() OVER (ORDER BY Count DESC) AS rn
    FROM Tags
    WHERE IsModeratorOnly = FALSE
),
UserVoteAgg AS (
    SELECT 
        p.OwnerUserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Posts p
    JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
),
LatestQuestionPerUser AS (
    SELECT 
        p.OwnerUserId,
        p.Id AS QuestionId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
),
RecentDuplicates AS (
    SELECT 
        ph.PostId,
        ph.CreationDate,
        CASE WHEN ph.Comment ~ '^\d+$' THEN CAST(ph.Comment AS INTEGER) END AS DuplicateOfId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10               -- Post Closed (duplicate reason stored in Comment)
      AND ph.Comment ~ '^\d+$'                    -- comment contains numeric duplicate id
),
MainResults AS (
SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - us.LastPostDate)) AS DaysSinceLastPost,
    tt.TagName,
    tt.Count                                             AS TagUsage,
    rd.DuplicateOfId,
    rd.CreationDate                                      AS DuplicateClosedDate,
    va.UpVotes,
    va.DownVotes,
    ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.QuestionCount DESC) AS ReputationRank
FROM UserStats us
LEFT JOIN TopTags tt 
       ON tt.rn = ((us.Id % 10) + 1)                      -- distribute tags across users
LEFT JOIN UserVoteAgg va 
       ON va.OwnerUserId = us.Id
LEFT JOIN LatestQuestionPerUser lq 
       ON lq.OwnerUserId = us.Id AND lq.rn = 1
LEFT JOIN RecentDuplicates rd 
       ON rd.PostId = lq.QuestionId AND rd.rn = 1
WHERE us.Reputation > 1000
ORDER BY ReputationRank
LIMIT 100
)

SELECT * FROM MainResults

UNION ALL

SELECT
    CAST(NULL AS INTEGER) AS Id,
    'Aggregated Summary' AS DisplayName,
    CAST(NULL AS BIGINT) AS Reputation,
    CAST(NULL AS INTEGER) AS QuestionCount,
    CAST(NULL AS INTEGER) AS AnswerCount,
    CAST(NULL AS INTEGER) AS GoldBadges,
    CAST(NULL AS INTEGER) AS SilverBadges,
    CAST(NULL AS INTEGER) AS BronzeBadges,
    CAST(NULL AS INTEGER) AS DaysSinceLastPost,
    CAST(NULL AS TEXT) AS TagName,
    CAST(NULL AS INTEGER) AS TagUsage,
    CAST(NULL AS INTEGER) AS DuplicateOfId,
    CAST(NULL AS TIMESTAMP) AS DuplicateClosedDate,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    CAST(NULL AS INTEGER) AS ReputationRank
FROM Votes v
WHERE v.VoteTypeId IN (2,3);