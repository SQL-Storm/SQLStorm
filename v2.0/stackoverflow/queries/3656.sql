-- {"query": "3656.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2817} 
WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(p.PostCount,0)               AS PostCount,
           COALESCE(a.AnswerCount,0)             AS AnswerCount,
           COALESCE(a.QuestionCount,0)           AS QuestionCount,
           COALESCE(b.GoldBadges,0)              AS GoldBadges,
           COALESCE(b.SilverBadges,0)            AS SilverBadges,
           COALESCE(b.BronzeBadges,0)            AS BronzeBadges,
           COALESCE(v.UpVotes,0) - COALESCE(v.DownVotes,0) AS VoteScore
    FROM Users u
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS PostCount
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
        GROUP BY OwnerUserId
    ) p  ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT OwnerUserId,
               SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
               SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
        GROUP BY OwnerUserId
    ) a  ON a.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT UserId,
               SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
               SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
               SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Badges
        GROUP BY UserId
    ) b  ON b.UserId = u.Id
    LEFT JOIN (
        SELECT UserId,
               SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
               SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes
        GROUP BY UserId
    ) v  ON v.UserId = u.Id
),

TopTags AS (
    SELECT t.TagName,
           COUNT(*) AS TagUseCount,
           ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rn
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS tag
    ) AS tlist
    JOIN Tags t ON t.TagName = tlist.tag
    WHERE p.PostTypeId = 1                    -- only questions
    GROUP BY t.TagName
),

UserTagActivity AS (
    SELECT us.Id            AS UserId,
           tt.TagName,
           COUNT(*)         AS PostsWithTag
    FROM UserStats us
    JOIN Posts p ON p.OwnerUserId = us.Id AND p.PostTypeId = 1
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS tag
    ) AS tlist
    JOIN Tags t  ON t.TagName = tlist.tag
    JOIN TopTags tt ON tt.TagName = t.TagName AND tt.rn <= 5
    GROUP BY us.Id, tt.TagName
),

UserScoreRanking AS (
    SELECT us.Id,
           us.DisplayName,
           us.Reputation,
           us.PostCount,
           us.VoteScore,
           RANK() OVER (ORDER BY (us.Reputation + us.VoteScore) DESC) AS RepVoteRank,
           ROW_NUMBER() OVER (
               PARTITION BY CASE WHEN us.Reputation > 10000 THEN 'high' ELSE 'regular' END
               ORDER BY us.PostCount DESC
           ) AS RowInGroup
    FROM UserStats us
)

SELECT ustat.Id,
       ustat.DisplayName,
       ustat.Reputation,
       ustat.PostCount,
       ustat.AnswerCount,
       ustat.QuestionCount,
       ustat.GoldBadges,
       ustat.SilverBadges,
       ustat.BronzeBadges,
       ustat.VoteScore,
       urank.RepVoteRank,
       urank.RowInGroup,
       COALESCE(uta.TagName, 'None')            AS TopTag,
       COALESCE(uta.PostsWithTag,0)            AS PostsWithTopTag,
       (SELECT MAX(p.CreationDate)
        FROM Posts p
        WHERE p.OwnerUserId = ustat.Id)        AS LatestPostDate
FROM UserScoreRanking urank
JOIN UserStats ustat          ON ustat.Id = urank.Id
LEFT JOIN (
    SELECT UserId,
           TagName,
           PostsWithTag,
           ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY PostsWithTag DESC) AS rn
    FROM UserTagActivity
) uta ON uta.UserId = ustat.Id AND uta.rn = 1
WHERE urank.RowInGroup <= 3

UNION ALL

SELECT NULL,
       '--- Summary ---',
       NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
FROM (SELECT 1) s

ORDER BY RepVoteRank;