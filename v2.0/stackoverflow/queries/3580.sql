-- {"query": "3580.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3534}
WITH 
user_stats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS NetVotes,
        (SELECT COUNT(*) FROM Posts p 
         WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p 
         WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT AVG(p.Score) FROM Posts p 
         WHERE p.OwnerUserId = u.Id 
           AND p.PostTypeId = 2 
           AND p.CreationDate < DATE '2023-01-01') AS AvgAnswerScorePre2023,
        (SELECT COUNT(*) FROM Badges b 
         WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgeCount
    FROM Users u
),
tag_agg AS (
    SELECT 
        u.Id                         AS UserId,
        TRIM(t.tag)                  AS Tag,
        COUNT(*)                     AS TagUseCount
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    CROSS JOIN LATERAL (
      SELECT UNNEST(string_to_array(REPLACE(REPLACE(p.Tags,'<',''),'>',''), ',')) AS tag
    ) t
    WHERE p.Tags IS NOT NULL
    GROUP BY u.Id, TRIM(t.tag)
),
top_tags AS (
    SELECT 
        UserId,
        STRING_AGG(Tag || ':' || CAST(TagUseCount AS VARCHAR), ', ' ORDER BY TagUseCount DESC) AS TopTags
    FROM (
        SELECT 
            UserId,
            Tag,
            TagUseCount,
            ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagUseCount DESC) AS rn
        FROM tag_agg
    ) t
    WHERE rn <= 5
    GROUP BY UserId
),
post_activity AS (
    SELECT 
        p.OwnerUserId,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Qs,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS As,
        MAX(p.LastActivityDate)                               AS LastActivity,
        SUM(COALESCE(p.ViewCount,0))                          AS TotalViews
    FROM Posts p
    GROUP BY p.OwnerUserId
),
badge_summary AS (
    SELECT 
        b.UserId,
        COUNT(*)                              AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)   AS Gold,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)   AS Silver,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)   AS Bronze
    FROM Badges b
    GROUP BY b.UserId
),
vote_summary AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    GROUP BY v.PostId
),
user_score AS (
    SELECT 
        u.Id,
        COALESCE(us.NetVotes,0) +
        COALESCE(pa.TotalViews,0)/100.0 +
        COALESCE(bs.Gold,0)*10 +
        COALESCE(vs.UpVotes,0)*0.5 -
        COALESCE(vs.DownVotes,0)*0.5 AS CompositeScore
    FROM Users u
    LEFT JOIN user_stats us      ON us.Id = u.Id
    LEFT JOIN post_activity pa  ON pa.OwnerUserId = u.Id
    LEFT JOIN badge_summary bs  ON bs.UserId = u.Id
    LEFT JOIN (
        SELECT 
            p.OwnerUserId AS UserId,
            SUM(COALESCE(vs.UpVotes,0))   AS UpVotes,
            SUM(COALESCE(vs.DownVotes,0)) AS DownVotes
        FROM Posts p
        LEFT JOIN vote_summary vs ON vs.PostId = p.Id
        GROUP BY p.OwnerUserId
    ) vs ON vs.UserId = u.Id
)

SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.AvgAnswerScorePre2023,
    us.GoldBadgeCount,
    COALESCE(pa.Qs,0)                         AS TotalQuestions,
    COALESCE(pa.As,0)                         AS TotalAnswers,
    pa.LastActivity,
    COALESCE(bs.TotalBadges,0)                AS TotalBadges,
    bs.Gold,
    bs.Silver,
    bs.Bronze,
    tt.TopTags,
    us.NetVotes,
    COALESCE(vs.UpVotes,0)                    AS PostUpVotes,
    COALESCE(vs.DownVotes,0)                  AS PostDownVotes,
    us.NetVotes + COALESCE(vs.UpVotes,0) - COALESCE(vs.DownVotes,0) AS NetVoteScore,
    us.NetVotes * LOG(GREATEST(u.Reputation,1))                AS ReputationWeightedVotes,
    us.NetVotes * CASE WHEN u.Location IS NULL THEN 0.5 ELSE 1 END 
                                                AS LocationAdjustedVotes,
    us.NetVotes / NULLIF(COALESCE(us.QuestionCount,0) + COALESCE(us.AnswerCount,0),0) AS AvgNetVotesPerPost,
    CASE
        WHEN u.Reputation > 20000 THEN 'Elite'
        WHEN u.Reputation > 10000 THEN 'Veteran'
        WHEN u.Reputation > 2000  THEN 'Contributor'
        ELSE 'Newbie'
    END                                      AS UserTier,
    ROW_NUMBER() OVER (ORDER BY us.NetVotes DESC)       AS ReputationRank,
    RANK()       OVER (ORDER BY us.NetVotes DESC)       AS NetVoteRank,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC)     AS ReputationDenseRank,
    us.NetVotes + COALESCE(bs.TotalBadges,0)*5          AS FinalScore
FROM Users u
LEFT JOIN user_stats      us ON us.Id = u.Id
LEFT JOIN post_activity   pa ON pa.OwnerUserId = u.Id
LEFT JOIN badge_summary   bs ON bs.UserId = u.Id
LEFT JOIN top_tags        tt ON tt.UserId = u.Id
LEFT JOIN (
    SELECT 
        p.OwnerUserId AS UserId,
        SUM(COALESCE(vs.UpVotes,0))   AS UpVotes,
        SUM(COALESCE(vs.DownVotes,0)) AS DownVotes
    FROM Posts p
    LEFT JOIN vote_summary vs ON vs.PostId = p.Id
    GROUP BY p.OwnerUserId
) vs ON vs.UserId = u.Id
WHERE (u.CreationDate < DATE '2010-01-01' OR u.CreationDate IS NULL)
  AND (u.Location IS NOT NULL OR u.WebsiteUrl IS NOT NULL)
  AND (us.QuestionCount IS NOT NULL OR us.AnswerCount IS NOT NULL)

UNION ALL

SELECT
    -1                                    AS Id,
    'Anonymous'                           AS DisplayName,
    0                                     AS Reputation,
    CAST(0 AS INTEGER)                    AS QuestionCount,
    CAST(0 AS INTEGER)                    AS AnswerCount,
    CAST(NULL AS NUMERIC)                 AS AvgAnswerScorePre2023,
    CAST(NULL AS INTEGER)                 AS GoldBadgeCount,
    CAST(0 AS INTEGER)                    AS TotalQuestions,
    CAST(0 AS INTEGER)                    AS TotalAnswers,
    CAST(NULL AS TIMESTAMP)               AS LastActivity,
    CAST(0 AS INTEGER)                    AS TotalBadges,
    CAST(0 AS INTEGER)                    AS Gold,
    CAST(0 AS INTEGER)                    AS Silver,
    CAST(0 AS INTEGER)                    AS Bronze,
    CAST('' AS VARCHAR)                   AS TopTags,
    CAST(0 AS INTEGER)                    AS NetVotes,
    CAST(0 AS INTEGER)                    AS PostUpVotes,
    CAST(0 AS INTEGER)                    AS PostDownVotes,
    CAST(0 AS NUMERIC)                    AS NetVoteScore,
    CAST(0 AS NUMERIC)                    AS ReputationWeightedVotes,
    CAST(0 AS NUMERIC)                    AS LocationAdjustedVotes,
    CAST(0 AS NUMERIC)                    AS AvgNetVotesPerPost,
    CAST('' AS VARCHAR)                   AS UserTier,
    CAST(0 AS INTEGER)                    AS ReputationRank,
    CAST(0 AS INTEGER)                    AS NetVoteRank,
    CAST(0 AS INTEGER)                    AS ReputationDenseRank,
    CAST(0 AS NUMERIC)                    AS FinalScore
FROM (SELECT 1) AS dummy

ORDER BY FinalScore DESC
LIMIT 100;