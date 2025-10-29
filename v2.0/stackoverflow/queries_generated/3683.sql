-- {"query": "3683.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2046} 

WITH UserPosts AS (
    SELECT
        u.Id                                   AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END)                     AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END)                     AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2))                AS AvgPostScore,
        MAX(p.CreationDate)                                            AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserBadges AS (
    SELECT
        b.UserId,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)                    AS HasGold,
        MAX(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)                    AS HasSilver,
        MAX(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)                    AS HasBronze,
        COUNT(*)                                                       AS TotalBadges,
        MAX(b.Date)                                                    AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
UserVotes AS (
    SELECT
        v.PostId,
        p.OwnerUserId                                                    AS OwnerId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)               AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)               AS DownVotesReceived
    FROM Votes v
    JOIN Posts p ON p.Id = v.PostId
    GROUP BY v.PostId, p.OwnerUserId
),
AggregatedVotes AS (
    SELECT
        OwnerId,
        SUM(UpVotesReceived)                                            AS TotalUpVotes,
        SUM(DownVotesReceived)                                          AS TotalDownVotes
    FROM UserVotes
    GROUP BY OwnerId
),
TagStats AS (
    SELECT
        t.TagName,
        COUNT(p.Id)                                                     AS PostCount,
        SUM(p.Score)                                                    AS TotalScore,
        MAX(p.CreationDate)                                             AS LatestPost
    FROM Tags t
    JOIN Posts p
      ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
     AND p.PostTypeId = 1
    GROUP BY t.TagName
)

SELECT
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.QuestionCount,
    up.AnswerCount,
    ROUND(up.AvgPostScore, 2)                                         AS AvgScore,
    COALESCE(av.TotalUpVotes, 0)                                      AS UpVotes_Received,
    COALESCE(av.TotalDownVotes, 0)                                    AS DownVotes_Received,
    ub.HasGold,
    ub.HasSilver,
    ub.HasBronze,
    ub.TotalBadges,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - GREATEST(up.LastPostDate, ub.LatestBadgeDate))) 
                                                                      AS SecondsSinceLastActivity,
    ROW_NUMBER() OVER (ORDER BY up.Reputation DESC, up.QuestionCount DESC) 
                                                                      AS ReputationRank,
    CASE
        WHEN up.QuestionCount = 0 THEN NULL
        ELSE up.QuestionCount::float / NULLIF(up.AnswerCount, 0)
    END                                                               AS QtoARatio,
    CONCAT('User_', up.UserId)                                        AS UserKey
FROM UserPosts up
LEFT JOIN UserBadges ub   ON ub.UserId = up.UserId
LEFT JOIN AggregatedVotes av ON av.OwnerId = up.UserId
WHERE (up.Reputation > 1000 OR ub.TotalBadges > 10)
  AND (up.QuestionCount + up.AnswerCount) > 0

UNION ALL

SELECT
    NULL                                                            AS UserId,
    NULL                                                            AS DisplayName,
    NULL                                                            AS Reputation,
    NULL                                                            AS QuestionCount,
    NULL                                                            AS AnswerCount,
    NULL                                                            AS AvgScore,
    NULL                                                            AS UpVotes_Received,
    NULL                                                            AS DownVotes_Received,
    NULL                                                            AS HasGold,
    NULL                                                            AS HasSilver,
    NULL                                                            AS HasBronze,
    NULL                                                            AS TotalBadges,
    NULL                                                            AS SecondsSinceLastActivity,
    NULL                                                            AS ReputationRank,
    NULL                                                            AS QtoARatio,
    t.TagName                                                       AS UserKey
FROM TagStats t
WHERE t.PostCount > 1000

ORDER BY ReputationRank NULLS LAST, UserKey
LIMIT 200;
