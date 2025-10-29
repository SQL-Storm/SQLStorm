-- {"query": "3583.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2240} 

WITH 
-- Count badges per user, split by class
UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldCount,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverCount,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeCount
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),

-- Aggregate post statistics per owner
UserPostStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

-- Votes cast by each user
UserVoteStats AS (
    SELECT 
        v.UserId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.UserId
),

-- Expand tags per post and associate them with the owner
PostTagAffinities AS (
    SELECT 
        p.OwnerUserId AS UserId,
        LOWER(t.TagName) AS TagName
    FROM Posts p
    JOIN LATERAL (
        SELECT unnest(
            string_to_array(
                substring(p.Tags FROM 2 FOR length(p.Tags)-2),
                '><'
            )
        )::int AS TagId
    ) AS tag_ids ON true
    JOIN Tags t ON t.Id = tag_ids.TagId
    WHERE p.Tags IS NOT NULL
)

SELECT
    u.Id,
    COALESCE(u.DisplayName, '<deleted>')           AS DisplayName,
    u.Reputation,
    ub.GoldCount,
    ub.SilverCount,
    ub.BronzeCount,
    ups.QuestionCount,
    ups.AnswerCount,
    ROUND(COALESCE(ups.AvgScore,0),2)              AS AvgPostScore,
    ups.LastPostDate,
    uv.UpVotesGiven,
    uv.DownVotesGiven,
    uv.LastVoteDate,
    CASE
        WHEN ub.GoldCount > 0               THEN 'PowerUser'
        WHEN ub.SilverCount > 5             THEN 'Experienced'
        ELSE                                      'Novice'
    END                                           AS UserTier,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
    STRING_AGG(DISTINCT pta.TagName, ', ')        AS TagAffinity
FROM Users u
LEFT JOIN UserBadgeCounts ub   ON ub.UserId = u.Id
LEFT JOIN UserPostStats ups    ON ups.UserId = u.Id
LEFT JOIN UserVoteStats uv    ON uv.UserId = u.Id
LEFT JOIN PostTagAffinities pta ON pta.UserId = u.Id
WHERE u.CreationDate < CURRENT_DATE - INTERVAL '1 year'
  AND (u.Location IS NULL OR POSITION('USA' IN u.Location) = 0)
GROUP BY 
    u.Id, ub.GoldCount, ub.SilverCount, ub.BronzeCount,
    ups.QuestionCount, ups.AnswerCount, ups.AvgScore, ups.LastPostDate,
    uv.UpVotesGiven, uv.DownVotesGiven, uv.LastVoteDate, u.Reputation,
    u.DisplayName
HAVING COUNT(*) FILTER (WHERE ups.QuestionCount > 10) > 0

UNION ALL

SELECT
    NULL                                        AS Id,
    'Aggregate'                                 AS DisplayName,
    NULL                                        AS Reputation,
    SUM(ub.GoldCount)                           AS GoldCount,
    SUM(ub.SilverCount)                         AS SilverCount,
    SUM(ub.BronzeCount)                         AS BronzeCount,
    SUM(ups.QuestionCount)                      AS QuestionCount,
    SUM(ups.AnswerCount)                        AS AnswerCount,
    ROUND(AVG(ups.AvgScore),2)                  AS AvgPostScore,
    MAX(ups.LastPostDate)                       AS LastPostDate,
    SUM(uv.UpVotesGiven)                        AS UpVotesGiven,
    SUM(uv.DownVotesGiven)                      AS DownVotesGiven,
    MAX(uv.LastVoteDate)                        AS LastVoteDate,
    NULL                                        AS UserTier,
    NULL                                        AS ReputationRank,
    NULL                                        AS TagAffinity
FROM UserBadgeCounts ub
JOIN UserPostStats ups ON ups.UserId = ub.UserId
LEFT JOIN UserVoteStats uv ON uv.UserId = ub.UserId;
