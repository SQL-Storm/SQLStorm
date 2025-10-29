-- {"query": "3443.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2270} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)                         AS NetVotes,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id 
                                      AND p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL) AS QuestionsWithAccepted
    FROM Users u
),
TagActivity AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)                               AS QCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)                               AS ACount,
        AVG(p.Score)                                                              AS AvgScore,
        STRING_AGG(DISTINCT u.DisplayName, ', ') 
            FILTER (WHERE u.Id IS NOT NULL)                                      AS TopContributors
    FROM Tags t
    LEFT JOIN Posts p 
        ON p.Tags LIKE CONCAT('%<', t.TagName, '>%') 
       AND p.PostTypeId IN (1,2)
    LEFT JOIN Users u 
        ON u.Id = p.OwnerUserId
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 0
),
RecentVotes AS (
    SELECT 
        v.PostId,
        v.VoteTypeId,
        v.UserId,
        v.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rn
    FROM Votes v
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
)
SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.NetVotes,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.QuestionCount,
    us.AnswerCount,
    us.QuestionsWithAccepted,
    COALESCE(q.Title, a.Title)                                 AS RecentPostTitle,
    CASE 
        WHEN q.Id IS NOT NULL THEN 'Question'
        WHEN a.Id IS NOT NULL THEN 'Answer'
        ELSE NULL
    END                                                       AS RecentPostType,
    COALESCE(rv.VoteTypeId, 0)                                 AS RecentVoteType,
    rv.CreationDate                                            AS RecentVoteDate,
    ta.TagName,
    ta.QCount,
    ta.ACount,
    ta.AvgScore,
    ta.TopContributors
FROM UserStats us
LEFT JOIN LATERAL (
    SELECT p.Id, p.Title, p.PostTypeId
    FROM Posts p
    WHERE p.OwnerUserId = us.Id
      AND p.CreationDate = (
          SELECT MAX(p2.CreationDate)
          FROM Posts p2
          WHERE p2.OwnerUserId = us.Id
      )
    LIMIT 1
) recent_post ON TRUE
LEFT JOIN Posts q ON q.Id = recent_post.Id AND q.PostTypeId = 1
LEFT JOIN Posts a ON a.Id = recent_post.Id AND a.PostTypeId = 2
LEFT JOIN RecentVotes rv 
    ON rv.PostId = recent_post.Id 
   AND rv.rn = 1
LEFT JOIN TagActivity ta 
    ON ta.TagName = ANY (
        SELECT unnest(string_to_array(
            REPLACE(REPLACE(recent_post.Title, '<', ''), '>', ''), ' '))
    )
WHERE us.Reputation > 1000
  AND (us.GoldBadges + us.SilverBadges + us.BronzeBadges) >= 10
ORDER BY us.Reputation DESC
LIMIT 100

UNION ALL

SELECT
    NULL               AS Id,
    'Aggregate'        AS DisplayName,
    NULL               AS Reputation,
    NULL               AS NetVotes,
    SUM(us.GoldBadges)   AS GoldBadges,
    SUM(us.SilverBadges) AS SilverBadges,
    SUM(us.BronzeBadges) AS BronzeBadges,
    SUM(us.QuestionCount) AS QuestionCount,
    SUM(us.AnswerCount)   AS AnswerCount,
    SUM(us.QuestionsWithAccepted) AS QuestionsWithAccepted,
    NULL AS RecentPostTitle,
    NULL AS RecentPostType,
    NULL AS RecentVoteType,
    NULL AS RecentVoteDate,
    NULL AS TagName,
    NULL AS QCount,
    NULL AS ACount,
    NULL AS AvgScore,
    NULL AS TopContributors
FROM UserStats us
WHERE us.Reputation BETWEEN 500 AND 2000
  AND us.NetVotes IS NOT NULL;
